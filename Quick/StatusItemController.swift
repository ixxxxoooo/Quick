// StatusItemController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit

/// 菜单栏状态项控制器
///
/// 使用 AppKit `NSStatusItem` 替代 SwiftUI `MenuBarExtra`，
/// 避免与面板窗口产生主菜单死循环。
@MainActor
final class StatusItemController {

    private var statusItem: NSStatusItem?

    /// 安装菜单栏图标与菜单
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "command.circle.fill",
                accessibilityDescription: "Quick"
            )
            button.toolTip = "Quick"
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: "显示 Quick",
                action: #selector(showPalette),
                keyEquivalent: ""
            ))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "退出 Quick",
                action: #selector(quit),
                keyEquivalent: "q"
            ))
        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    /// 移除菜单栏图标
    func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    @objc private func showPalette() {
        AppCore.shared.paletteCoordinator.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
