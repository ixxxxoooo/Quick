// SuperPanelSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 超级面板设置页
struct SuperPanelSettingsView: View {

    @AppStorage(PluginSettingKey.SuperPanel.autoDetect) private var autoDetect = true
    @AppStorage(PluginSettingKey.SuperPanel.showGitActions) private var showGitActions = true
    @AppStorage(PluginSettingKey.SuperPanel.showBuildActions) private var showBuildActions = true
    @AppStorage(PluginSettingKey.SuperPanel.showFileNav) private var showFileNav = true
    @AppStorage(PluginSettingKey.SuperPanel.preferredTerminal) private var preferredTerminal = "Terminal"
    @AppStorage(PluginSettingKey.SuperPanel.showClipboard) private var showClipboard = true
    @AppStorage(PluginSettingKey.SuperPanel.showQuickTools) private var showQuickTools = true

    var body: some View {
        Form {
            Section("工作台") {
                Toggle("显示常用工具", isOn: $showQuickTools)
                Toggle("显示剪贴板预览", isOn: $showClipboard)
            }

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

            Section("项目操作") {
                Toggle("Git 操作", isOn: $showGitActions)
                Toggle("构建命令", isOn: $showBuildActions)
                Toggle("文件导航", isOn: $showFileNav)
            }
        }
        .formStyle(.grouped)
    }
}
