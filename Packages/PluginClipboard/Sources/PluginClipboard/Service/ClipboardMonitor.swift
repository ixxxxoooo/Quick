// ClipboardMonitor.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

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

    /// 是否正在监听
    private(set) var isRunning = false

    /// 开始监听
    ///
    /// 幂等：设置页每写一次偏好都会让插件重新按开关起停一次，不幂等的话每次都会新建
    /// 一个定时器并重置变更计数，等于反复丢掉「刚才那半秒里复制的东西」。
    func start() {
        guard !isRunning else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
        isRunning = true
    }

    /// 停止监听
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// 检测剪贴板变化
    private func checkForChanges() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // 来源取「此刻的前台应用」。macOS 不提供剪贴板归属，这是轮询方案能做到的最好近似
        let source = Self.frontmostSource()

        // 优先检测图片。转码离开主线程，避免复制大图时卡住面板
        if captureImage(from: pasteboard, source: source) {
            return
        }

        // 检测文本
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        let type = detectContentType(text)
        let entry = ClipboardEntry(
            text: text,
            type: type,
            sourceAppName: source.name,
            sourceBundleID: source.bundleID
        )
        onNewContent?(entry)
    }

    /// 记录来源应用（名称 + Bundle ID）
    private struct Source: Sendable {
        let name: String?
        let bundleID: String?
    }

    /// 取当前前台应用作为剪贴板来源
    private static func frontmostSource() -> Source {
        let app = NSWorkspace.shared.frontmostApplication
        return Source(name: app?.localizedName, bundleID: app?.bundleIdentifier)
    }

    /// 发现图片就在后台转成 PNG。返回 true 表示这次变化按图片处理，不再记文本
    private func captureImage(from pasteboard: NSPasteboard, source: Source) -> Bool {
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        guard pasteboard.availableType(from: imageTypes) != nil,
            let image = NSImage(pasteboard: pasteboard),
            let tiffData = image.tiffRepresentation
        else { return false }

        let size = image.size
        let sizeDesc = "\(Int(size.width))×\(Int(size.height))"
        let changeCount = pasteboard.changeCount
        Task.detached {
            let pngData = Self.pngData(fromTIFF: tiffData)
            await MainActor.run { [weak self] in
                self?.deliverImage(
                    pngData,
                    sizeDescription: sizeDesc,
                    changeCount: changeCount,
                    source: source
                )
            }
        }
        return true
    }

    /// PNG 编码不碰 AppKit 视图，可以离开主线程
    nonisolated private static func pngData(fromTIFF tiff: Data) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// 图片转码结束。期间如果剪贴板又变了，丢掉这张过期图
    private func deliverImage(_ pngData: Data?, sizeDescription: String, changeCount: Int, source: Source) {
        guard lastChangeCount == changeCount else { return }
        guard let pngData else { return }
        guard pngData.count <= 5 * 1024 * 1024 else {
            QuickLog.plugin("clipboard").notice("剪贴板图片超过 5MB，已跳过")
            return
        }
        onNewContent?(
            ClipboardEntry(
                imageData: pngData,
                sizeDescription: sizeDescription,
                sourceAppName: source.name,
                sourceBundleID: source.bundleID
            ))
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
