// SuperPanelSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 超级面板设置页
///
/// 配置项目检测行为和默认操作。
struct SuperPanelSettingsView: View {

    /// 是否自动检测项目
    @AppStorage(PluginSettingKey.SuperPanel.autoDetect) private var autoDetect = true

    /// 是否显示 Git 操作
    @AppStorage(PluginSettingKey.SuperPanel.showGitActions) private var showGitActions = true

    /// 是否显示构建操作
    @AppStorage(PluginSettingKey.SuperPanel.showBuildActions) private var showBuildActions = true

    /// 是否显示文件导航
    @AppStorage(PluginSettingKey.SuperPanel.showFileNav) private var showFileNav = true

    /// 首选终端
    @AppStorage(PluginSettingKey.SuperPanel.preferredTerminal) private var preferredTerminal = "Terminal"

    var body: some View {
        Form {
            Section("项目检测") {
                Toggle("自动检测前台应用的项目", isOn: $autoDetect)

                Picker("首选终端", selection: $preferredTerminal) {
                    Text("Terminal").tag("Terminal")
                    Text("iTerm2").tag("iTerm2")
                    Text("Warp").tag("Warp")
                    Text("Kitty").tag("Kitty")
                    Text("Alacritty").tag("Alacritty")
                }
            }

            Section("显示操作") {
                Toggle("Git 操作", isOn: $showGitActions)
                Toggle("构建命令", isOn: $showBuildActions)
                Toggle("文件导航", isOn: $showFileNav)
            }
        }
        .formStyle(.grouped)
    }
}
