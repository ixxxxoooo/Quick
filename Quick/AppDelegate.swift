// AppDelegate.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickUI

/// AppKit 生命周期代理
///
/// 管理应用启动、退出、Dock 图标点击等 AppKit 层事件。
/// 将所有业务逻辑委托给 AppCore，自身不持有任何状态。
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 应用完成启动
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 主菜单要在任何窗口出现之前装好：⌘A / ⌘C / ⌘V 这些靠它的菜单项派发，
        // 没有菜单就完全没人处理（见 MainMenu 的说明）
        MainMenu.install()

        // accessory 模式已在 QuickMain 中设置；此处仅启动核心
        AppCore.shared.start()

        // 开发参数：直接打开某个插件的面板（验收用，和 -showPalette / -showSettings 同类）
        if let index = CommandLine.arguments.firstIndex(of: "-showPlugin"),
            index + 1 < CommandLine.arguments.count
        {
            let pluginID = CommandLine.arguments[index + 1]
            AppCore.shared.paletteCoordinator.show(pluginID: pluginID)
        } else if CommandLine.arguments.contains("-showSettings") {
            AppCore.shared.settingsWindowController.show(tab: .applications)
        } else if CommandLine.arguments.contains("-showPalette") {
            AppCore.shared.paletteCoordinator.show()
        }
    }

    /// 应用即将退出
    func applicationWillTerminate(_ notification: Notification) {
        AppCore.shared.prepareForTermination()
    }

    /// Dock 图标被点击（accessory 模式下不触发，保留以防切换）
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        AppCore.shared.paletteCoordinator.toggle()
        return true
    }

    /// 不因最后一个窗口关闭而退出（作为常驻后台应用）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
