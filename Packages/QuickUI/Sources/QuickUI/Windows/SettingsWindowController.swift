// SettingsWindowController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI

/// 设置窗口控制器
///
/// 一个**普通窗口**，不是面板：它有标题栏、可关闭，跟随系统的窗口语言。
/// 面板那套（无边框、非激活、跨空间）在这里全都不适用。
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {

    private let dataSource: any SettingsDataSource
    private let log = QuickLog.ui
    private var window: NSWindow?

    /// 初始化
    /// - Parameter dataSource: 由组装层注入（AppCore 实现）
    public init(dataSource: any SettingsDataSource) {
        self.dataSource = dataSource
        super.init()
    }

    /// 显示设置窗口（已存在则前置，不重建）
    public func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        // 我们是 accessory 应用（LSUIElement，没有 Dock 图标）：不显式激活的话，
        // 窗口会被推到最前面却拿不到键盘焦点 —— 点一下才响应，看起来像卡住。
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        log.notice("设置窗口已显示")
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: DesignTokens.Size.settingsWindow),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quick 设置"
        window.contentView = NSHostingView(rootView: SettingsView(dataSource: dataSource))
        // 关掉不释放，下次 show() 直接复用 —— 重建会让窗口位置和滚动位置丢失。
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        log.debug("设置窗口已关闭")
    }
}
