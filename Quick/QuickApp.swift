// QuickApp.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickPlatform

/// 应用入口（纯 AppKit）
///
/// 不使用 SwiftUI `App` / `MenuBarExtra`：在 macOS 26 上，MenuBarExtra-only
/// 应用一旦出现任意窗口，会陷入 `makeMainMenu` 无限重建（CPU 100%）。
/// 菜单栏图标改由 `StatusItemController`（NSStatusItem）管理。
@main
enum QuickMain {
    static func main() {
        // 单实例检查：若已有实例运行，唤起主实例并退出当前进程
        guard SingleInstanceGuard.shared.ensureSingleInstance() else {
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
