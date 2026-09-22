// PasteService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import ApplicationServices
import CoreGraphics

/// 合成系统粘贴（⌘V）
///
/// macOS 没有「把剪贴板粘进当前应用」的公开 API，唯一手段是合成一次 ⌘V 键盘事件。
/// 这需要**辅助功能权限**：没授权时 `CGEvent.post` 会被系统静默丢弃，所以这里先自检
/// `AXIsProcessTrusted()`，把「没权限」和「发失败了」区分开。
@MainActor
public final class PasteService {

    /// kVK_ANSI_V：字母 V 的虚拟键码
    private static let vKeyCode: CGKeyCode = 0x09

    public init() {}

    /// 当前是否具备合成键盘事件所需的辅助功能权限
    public var canSynthesize: Bool { AXIsProcessTrusted() }

    /// 合成一次 ⌘V
    ///
    /// - Returns: `false` 表示没有辅助功能权限，事件没有发出；调用方应退化成「只完成复制」。
    @discardableResult
    public func paste() -> Bool {
        guard canSynthesize else { return false }

        // `.combinedSessionState` 跟随当前登录会话；用 HID 事件源投递才能被前台应用当成真实按键
        guard let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
