// PalettePanel.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 无边框非激活浮窗面板
///
/// Spotlight/Raycast 风格的命令面板。核心特性：
/// - 非激活面板：不抢夺其他应用的焦点（nonactivatingPanel）
/// - 无边框：使用自定义毛玻璃背景
/// - 跨空间：在所有桌面空间和全屏应用上层可见
/// - 浮动层级：始终保持在其他窗口之上
/// - 键盘驱动：拦截 Escape、Backspace、⌘ 快捷键等
public final class PalettePanel: NSPanel {

    /// 裸退格键回调（搜索框为空时退回上一层）
    var onBareBackspace: (() -> Bool)?

    /// Escape 键回调
    var onEscape: (() -> Bool)?

    /// ⌘ 快捷键回调（搜索框编辑器拦截前处理）
    var onCommandShortcut: ((NSEvent) -> Bool)?

    /// 上下键回调（`-1` 上移、`+1` 下移），返回 `true` 表示已消费
    var onMove: ((Int) -> Bool)?

    /// 回车回调，返回 `true` 表示已消费
    var onSubmit: (() -> Bool)?

    /// 初始化面板
    /// - Parameter rootView: SwiftUI 根视图
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0,
                width: DesignTokens.Size.panelWidth,
                height: DesignTokens.Size.panelHeight
            ),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        acceptsMouseMovedEvents = true
        // 关键：菜单栏点击后应用会失活；默认 true 会导致面板立刻被隐藏
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.sizingOptions = []
        contentView = hosting
    }

    // MARK: - 按键拦截

    override public func sendEvent(_ event: NSEvent) {
        // Escape 键
        if event.type == .keyDown,
            Int(event.keyCode) == kVK_Escape,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            onEscape?() == true
        {
            return
        }

        // 裸退格键（搜索框为空时）
        if event.type == .keyDown,
            Int(event.keyCode) == kVK_Delete,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            onBareBackspace?() == true
        {
            return
        }

        // 上下键
        //
        // **必须在这里拦，不能挂在 SwiftUI 视图上。** 面板打开时焦点在搜索框里，
        // field editor 会先把上下键拿去移动光标；而挂在结果列表（既不是焦点、
        // 也不是输入框的祖先）上的 onKeyPress 永远收不到事件。
        // 允许 Shift：Shift+上下也该能选，没有理由禁用。
        if event.type == .keyDown,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control]),
            let delta = Self.verticalDelta(for: event),
            onMove?(delta) == true
        {
            return
        }

        // 回车（含小键盘回车）
        if event.type == .keyDown,
            Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control]),
            onSubmit?() == true
        {
            return
        }

        // ⌘ 快捷键
        if event.type == .keyDown,
            event.modifierFlags.contains(.command),
            onCommandShortcut?(event) == true
        {
            return
        }

        super.sendEvent(event)
    }

    // MARK: - 窗口行为

    /// 上下键对应的方向，其他键返回 `nil`
    private static func verticalDelta(for event: NSEvent) -> Int? {
        switch Int(event.keyCode) {
        case kVK_UpArrow: return -1
        case kVK_DownArrow: return 1
        default: return nil
        }
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }
}
