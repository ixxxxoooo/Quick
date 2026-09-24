// PluginIntroSection.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 插件页开头：开关和一段介绍
///
/// 每个插件在侧边栏里单独占一项，点进去先看到它是做什么的，再往下是它自己的设置。
/// 不设分组标题、开关标题里也不重复插件名 —— 窗口标题与侧边栏已经写着它了。
struct PluginIntroSection: View {

    let dataSource: any PluginSettingsDataSource
    let pluginID: String

    @State private var isEnabled: Bool

    init(dataSource: any PluginSettingsDataSource, pluginID: String) {
        self.dataSource = dataSource
        self.pluginID = pluginID
        _isEnabled = State(initialValue: dataSource.isPluginEnabled(pluginID))
    }

    private var plugin: SettingsPlugin? {
        dataSource.pluginEntries.first { $0.id == pluginID }
    }

    var body: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                SettingsRow(
                    title: "启用此插件",
                    subtitle: "开启后可在主面板搜索并使用。",
                    icon: { SettingsRowIcon(systemImage: plugin?.icon ?? "puzzlepiece.extension") }
                )
            }
            .onChange(of: isEnabled) { _, newValue in
                dataSource.setPluginEnabled(pluginID, enabled: newValue)
            }

            if let description = plugin?.description, !description.isEmpty {
                SettingsRow(
                    title: "简介",
                    subtitle: description,
                    icon: { SettingsRowIcon(systemImage: "info.circle") }
                )
            }
        }
    }
}
