// QuickApp.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 应用入口
///
/// SwiftUI App 生命周期入口，配合 AppDelegate 管理 AppKit 层事件。
/// 只负责声明 MenuBarExtra 和全局菜单命令，不持有任何业务逻辑。
@main
struct QuickApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// 是否显示菜单栏图标
    @AppStorage("quick.global.showInMenuBar") private var showInMenuBar = true

    var body: some Scene {
        // 菜单栏图标
        MenuBarExtra("Quick", systemImage: "command.circle.fill", isInserted: $showInMenuBar) {
            MenuBarMenu()
        }
        .commands {
            menuBarCommands
        }

        // 设置窗口
        Settings {
            SettingsView()
        }
    }

    /// 全局菜单命令
    @CommandsBuilder
    private var menuBarCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 Quick") {
                NSApp.orderFrontStandardAboutPanel()
            }
        }
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")
        }
    }
}

// MARK: - 菜单栏菜单

/// 菜单栏下拉菜单
struct MenuBarMenu: View {
    var body: some View {
        Button("显示 Quick") {
            AppCore.shared.paletteCoordinator.toggle()
        }

        Divider()

        Button("设置…") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        .keyboardShortcut(",")

        Divider()

        Button("退出 Quick") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - 设置视图（占位）

/// 设置窗口视图
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gear") }

            ModuleSettingsView()
                .tabItem { Label("模块", systemImage: "square.grid.2x2") }
        }
        .frame(width: 600, height: 400)
    }
}

/// 通用设置
struct GeneralSettingsView: View {
    @AppStorage("quick.global.showInMenuBar") private var showInMenuBar = true
    @AppStorage("quick.global.launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Toggle("显示菜单栏图标", isOn: $showInMenuBar)
            Toggle("开机自动启动", isOn: $launchAtLogin)
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// 模块设置（占位，后续由各模块提供）
struct ModuleSettingsView: View {
    var body: some View {
        VStack {
            Text("模块设置")
                .font(.title2)
            Text("各模块的设置将在这里显示")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
