// SuperPanelPanel.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 超级面板的无边框浮窗
///
/// 与 `PalettePanel` 同源：非激活面板 + 无边框 + 跨空间浮层，键盘事件在 AppKit 层
/// 拦截（焦点在 SwiftUI 视图上时，方向键与回车会被响应链先吃掉，挂在视图上收不到）。
final class SuperPanelPanel: NSPanel {

    /// Escape 回调，返回 `true` 表示已消费
    var onEscape: (() -> Bool)?
    /// 上下键回调（`-1` 上移、`+1` 下移）
    var onMove: ((Int) -> Bool)?
    /// 左右键回调（标签切换）
    var onTab: ((Int) -> Bool)?
    /// 回车回调
    var onSubmit: (() -> Bool)?
    /// 数字键回调（1 起）
    var onNumber: ((Int) -> Bool)?
    /// ⌥回车：替换原文
    var onReplace: (() -> Bool)?
    /// ⌘, 打开设置
    var onOpenSettings: (() -> Bool)?
    /// ⌘W 关闭
    var onClose: (() -> Void)?

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0,
                width: DesignTokens.Size.superPanelWidth,
                height: DesignTokens.Size.superPanelInitialHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        acceptsMouseMovedEvents = true
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
        // 固定宽度，高度由内容量出来后由协调器设置
        minSize = NSSize(
            width: DesignTokens.Size.superPanelWidth, height: DesignTokens.Size.superPanelMinHeight)
        maxSize = NSSize(
            width: DesignTokens.Size.superPanelWidth, height: DesignTokens.Size.superPanelMaxHeight)

        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else {
            super.sendEvent(event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ⌥回车：替换原文（必须在普通回车之前判断）
        if Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter,
            modifiers == .option, onReplace?() == true
        {
            return
        }

        // Escape
        if Int(event.keyCode) == kVK_Escape, modifiers.isEmpty, onEscape?() == true {
            return
        }

        // 上下键
        if modifiers.isDisjoint(with: [.command, .option, .control]),
            let delta = PalettePanel.verticalDelta(for: event), onMove?(delta) == true
        {
            return
        }

        // 左右键：标签切换
        if modifiers.isDisjoint(with: [.command, .option, .control]),
            let delta = PalettePanel.horizontalDelta(for: event), onTab?(delta) == true
        {
            return
        }

        // 回车
        if Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter,
            modifiers.isDisjoint(with: [.command, .option, .control]), onSubmit?() == true
        {
            return
        }

        // 数字键 1–9：直接执行第 n 项
        if modifiers.isEmpty,
            let chars = event.charactersIgnoringModifiers,
            chars.count == 1,
            let digit = Int(chars), (1...9).contains(digit),
            onNumber?(digit - 1) == true
        {
            return
        }

        // ⌘ 快捷键（不要求「只有 ⌘」：大写锁定之类的锁定位不该让 ⌘, 失效）
        if modifiers.contains(.command), let chars = event.charactersIgnoringModifiers?.lowercased() {
            if chars == ",", onOpenSettings?() == true { return }
            if chars == "w" {
                onClose?()
                return
            }
        }

        super.sendEvent(event)
    }
}
