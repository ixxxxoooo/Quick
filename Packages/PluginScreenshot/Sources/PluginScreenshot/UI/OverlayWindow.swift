// OverlayWindow.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit

/// 遮罩窗
///
/// 用 `NSPanel + .nonactivatingPanel`：全局热键触发时前台是别的 App，非激活面板
/// 不必先把 Quick 拉到前台就能拿到 key 与键盘焦点，也不会打断用户当前的操作。
final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
