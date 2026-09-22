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
///
/// **缩放与分离窗口同一套机制**：带 `.resizable` 让 AppKit 自己在四边提供缩放热区与光标，
/// 不再自绘一圈 `NSView` 去模拟（自绘那套既拿不到系统光标，也和分离窗口手感不一致）。
/// 尺寸的上下限在 `windowWillResize` 里夹好，缩放结束时写回 `PalettePreferences`。
public final class PalettePanel: NSPanel, NSWindowDelegate {

    /// 裸退格键回调（搜索框为空时退回上一层）
    var onBareBackspace: (() -> Bool)?

    /// Escape 键回调
    var onEscape: (() -> Bool)?

    /// ⌘W 关闭回调
    ///
    /// 与 Esc 分开：Esc 在搜索框有内容时只清空，而 ⌘W 的语义始终是「关掉这个面板」。
    /// 两者共用一个回调会让 ⌘W 退化成清空。
    var onClose: (() -> Void)?

    /// ⌘ 快捷键回调（搜索框编辑器拦截前处理）
    var onCommandShortcut: ((NSEvent) -> Bool)?

    /// 上下键回调（`-1` 上移、`+1` 下移），返回 `true` 表示已消费
    var onMove: ((Int) -> Bool)?

    /// 左右键回调（`-1` 左移、`+1` 右移），返回 `true` 表示已消费
    ///
    /// 主搜索里左右键属于搜索框的光标移动，只有插件内搜索（标签切换）才需要拦截。
    var onTab: ((Int) -> Bool)?

    /// 回车回调，返回 `true` 表示已消费
    var onSubmit: (() -> Bool)?

    /// 指针移动回调（用于检测是否有意移动鼠标）
    var onPointerMoved: ((CGPoint) -> Void)?

    /// 解除悬停激活回调（按键或滚轮触发）
    var onDisarmHover: ((CGPoint) -> Void)?

    /// 分离面板回调（⌘D 触发），返回 `true` 表示已消费
    var onDetach: (() -> Bool)?

    /// 初始化面板
    /// - Parameter rootView: SwiftUI 根视图
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0,
                width: DesignTokens.Size.panelWidth,
                height: DesignTokens.Size.panelHeight
            ),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel, .resizable],
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
        // 手动拖出来的尺寸与分离窗口一样有下限；上限交给 windowWillResize 按当前屏幕夹
        minSize = NSSize(
            width: DesignTokens.Size.panelMinWidth,
            height: DesignTokens.Size.panelMinHeight
        )
        // 系统缩放热区只有在 delegate 里夹尺寸时才可控
        delegate = self

        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.sizingOptions = []
        contentView = hosting
    }

    // MARK: - 缩放（与分离窗口同一套 AppKit 机制）

    /// 用户拖四边缩放时把尺寸夹在最值与当前屏幕之间
    ///
    /// 逻辑与旧的自绘边框完全一致（`PalettePreferences.clampedPanelWidth/Height`），
    /// 只是改由系统缩放路径回调。程序里的 `setContentSize`（换缩放档）不会走这里。
    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let screen = sender.screen ?? NSScreen.main
        let maxWidth = screen?.visibleFrame.width ?? frameSize.width
        let maxHeight = screen?.visibleFrame.height ?? frameSize.height
        return NSSize(
            width: PalettePreferences.clampedPanelWidth(frameSize.width, maxWidth: maxWidth),
            height: PalettePreferences.clampedPanelHeight(frameSize.height, maxHeight: maxHeight)
        )
    }

    /// 缩放结束才写回偏好，拖动过程中不落盘
    public func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        PalettePreferences.setPanelSize(window.frame.size)
    }

    // MARK: - 按键拦截

    override public func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved:
            onPointerMoved?(NSEvent.mouseLocation)
        case .keyDown, .scrollWheel:
            onDisarmHover?(NSEvent.mouseLocation)
        default:
            break
        }

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
        // 上下键（支持方向键与 Ctrl+N / Ctrl+P）
        if event.type == .keyDown,
            event.modifierFlags.isDisjoint(with: [.command, .option]),
            let delta = Self.verticalDelta(for: event),
            onMove?(delta) == true
        {
            return
        }

        // 左右键（插件内搜索的标签切换；主搜索里返回 false，键继续给搜索框光标）
        if event.type == .keyDown,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control]),
            let delta = Self.horizontalDelta(for: event),
            onTab?(delta) == true
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
            event.modifierFlags.contains(.command)
        {
            if let characters = event.charactersIgnoringModifiers {
                if characters == "," {
                    EventBus.shared.post(ShowPaletteSettingsEvent())
                    return
                }
                if characters.lowercased() == "w" {
                    onClose?()
                    return
                }
                // ⌘D：分离当前插件到独立窗口
                if characters.lowercased() == "d",
                    onDetach?() == true
                {
                    return
                }
            }
            if onCommandShortcut?(event) == true {
                return
            }
        }

        super.sendEvent(event)
    }

    // MARK: - 窗口行为

    /// 上下键对应的方向，其他键返回 `nil`
    ///
    /// 分离窗口（`DetachedPluginPanel`）复用同一份判定，保证两个窗口的方向键行为一致。
    static func verticalDelta(for event: NSEvent) -> Int? {
        if event.modifierFlags.contains(.control) {
            if let chars = event.charactersIgnoringModifiers {
                if chars.lowercased() == "n" { return 1 }
                if chars.lowercased() == "p" { return -1 }
            }
            return nil
        }
        switch Int(event.keyCode) {
        case kVK_UpArrow: return -1
        case kVK_DownArrow: return 1
        default: return nil
        }
    }

    /// 左右键对应的方向，其他键返回 `nil`
    static func horizontalDelta(for event: NSEvent) -> Int? {
        switch Int(event.keyCode) {
        case kVK_LeftArrow: return -1
        case kVK_RightArrow: return 1
        default: return nil
        }
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }
}
