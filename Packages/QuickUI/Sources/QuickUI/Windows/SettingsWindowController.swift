// SettingsWindowController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI

/// 设置窗口控制器
///
/// 参考 Tinycast 设计：
/// - 使用 AppKit 的 NSSplitViewController（SettingsSplitViewController）
/// - 工具栏集成 .sidebarTrackingSeparator，与 macOS 系统设置体验完全一致
/// - 纯净两栏布局，支持 ⌘W 关闭、⌘F 搜索设置
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {

    private let dataSource: any SettingsDataSource
    private let log = QuickLog.ui
    private var window: NSWindow?
    private var navigationState = SettingsNavigationState()
    private var toolbarController: SettingsToolbarController?

    /// 初始化
    /// - Parameter dataSource: 由组装层注入（AppCore 实现）
    public init(dataSource: any SettingsDataSource) {
        self.dataSource = dataSource
        super.init()
    }

    /// 显示设置窗口（已存在则前置，不重建）
    /// - Parameter tab: 可选的目标分栏
    public func show(tab: SettingsTab? = nil) {
        if let tab {
            navigationState.tab = tab
        }
        let window = self.window ?? makeWindow()
        self.window = window

        // 打开设置期间切成常规应用：accessory 应用不进 Dock、也不进 ⌘Tab 切换器，
        // 用户一旦切走就再也找不回来这个窗口。设置窗口是唯一一个「像普通窗口那样被对待」
        // 的界面，所以只在它开着的时候变成常规应用，关掉就变回去（见 windowWillClose）。
        NSApp.setActivationPolicy(.regular)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        log.notice("设置窗口已显示：\(self.navigationState.tab.title, privacy: .public)")
    }

    private func makeWindow() -> NSWindow {
        let style: NSWindow.StyleMask = [
            .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView
        ]
        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: DesignTokens.Size.settingsWindow),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = navigationState.tab.title
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.minSize = CGSize(
            width: DesignTokens.Size.settingsSidebar + DesignTokens.Size.settingsDetailMinimum,
            height: 480
        )

        let splitVC = SettingsSplitViewController(
            sidebar: SettingsSidebarView(dataSource: dataSource, navigationState: navigationState)
                .scrollContentBackground(.hidden),
            detail: SettingsDetailView(dataSource: dataSource, navigationState: navigationState)
                .scrollContentBackground(.hidden)
        )
        window.contentViewController = splitVC
        window.setContentSize(DesignTokens.Size.settingsWindow)

        let toolbar = SettingsToolbarController(navigationState: navigationState)
        self.toolbarController = toolbar
        toolbar.install(in: window)

        window.delegate = self
        window.center()
        return window
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        // 关掉设置就回到后台常驻：Dock 图标与 ⌘Tab 条目一起消失，
        // 这样它平时仍然是一个不占位的效率工具
        NSApp.setActivationPolicy(.accessory)

        log.debug("设置窗口已关闭")
    }
}

/// 支持 ⌘W 快捷关闭的设置窗口
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
            let chars = event.charactersIgnoringModifiers,
            chars.lowercased() == "w"
        {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
