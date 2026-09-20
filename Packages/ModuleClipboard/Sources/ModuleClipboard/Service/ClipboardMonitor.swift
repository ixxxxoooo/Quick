// ClipboardMonitor.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit

/// 剪贴板监听器
///
/// 定时轮询 NSPasteboard.general，检测剪贴板内容变化。
/// macOS 没有剪贴板变化的原生通知，必须轮询。
/// 支持文本和图片两类内容。
@MainActor
final class ClipboardMonitor {

    /// 新内容回调
    var onNewContent: ((ClipboardEntry) -> Void)?

    /// 轮询定时器
    private var timer: Timer?

    /// 上次检测到的变更计数
    private var lastChangeCount: Int = 0

    /// 开始监听
    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
    }

    /// 停止监听
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 检测剪贴板变化
    private func checkForChanges() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // 优先检测图片（有些应用同时放了文本和图片，图片优先）
        if let entry = detectImage(from: pasteboard) {
            onNewContent?(entry)
            return
        }

        // 检测文本
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        let type = detectContentType(text)
        let entry = ClipboardEntry(text: text, type: type)
        onNewContent?(entry)
    }

    /// 从剪贴板提取图片
    private func detectImage(from pasteboard: NSPasteboard) -> ClipboardEntry? {
        // 检查是否有图片类型数据（排除文件 URL 形式的图片引用）
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        guard pasteboard.availableType(from: imageTypes) != nil else { return nil }

        // 尝试读取为 NSImage
        guard let image = NSImage(pasteboard: pasteboard) else { return nil }

        // 转为 PNG 数据
        guard let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        // 图片太大就不存了（超过 5MB 跳过）
        guard pngData.count <= 5 * 1024 * 1024 else { return nil }

        let size = image.size
        let sizeDesc = "\(Int(size.width))×\(Int(size.height))"

        return ClipboardEntry(imageData: pngData, sizeDescription: sizeDesc)
    }

    /// 检测文本内容类型
    private func detectContentType(_ text: String) -> ClipboardEntry.ContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // URL 检测
        if let url = URL(string: trimmed), url.scheme != nil {
            return .url
        }

        // 颜色代码检测（#RRGGBB 或 rgb(...)）
        if trimmed.hasPrefix("#") && (trimmed.count == 7 || trimmed.count == 4) {
            return .color
        }

        // 代码检测（包含常见代码特征）
        let codeIndicators = ["{", "}", "func ", "class ", "import ", "let ", "var ", "const ", "function "]
        if codeIndicators.contains(where: { trimmed.contains($0) }) && trimmed.contains("\n") {
            return .code
        }

        return .text
    }
}
