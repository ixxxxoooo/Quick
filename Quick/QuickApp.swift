// QuickApp.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit

/// 应用入口（纯 AppKit）
///
/// 不使用 SwiftUI `App` / `MenuBarExtra`：在 macOS 26 上，MenuBarExtra-only
/// 应用一旦出现任意窗口，会陷入 `makeMainMenu` 无限重建（CPU 100%）。
/// 菜单栏图标改由 `StatusItemController`（NSStatusItem）管理。
@main
enum QuickMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
