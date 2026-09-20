// PasteboardService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit

/// 粘贴板读写服务
///
/// 封装 NSPasteboard 操作，提供统一的剪贴板读写接口。
@MainActor
public final class PasteboardService {

    public init() {}

    /// 复制文本到系统剪贴板
    /// - Parameter text: 要复制的文本
    public func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 读取系统剪贴板中的文本
    /// - Returns: 剪贴板文本内容
    public func readText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// 复制图片到系统剪贴板
    /// - Parameter image: 要复制的图片
    public func copyImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    /// 读取系统剪贴板中的图片
    /// - Returns: 剪贴板图片内容
    public func readImage() -> NSImage? {
        guard let data = NSPasteboard.general.data(forType: .tiff) else { return nil }
        return NSImage(data: data)
    }
}
