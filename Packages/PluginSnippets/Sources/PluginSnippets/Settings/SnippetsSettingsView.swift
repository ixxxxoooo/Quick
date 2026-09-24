// SnippetsSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct SnippetsSettingsView: View {
    @AppStorage(PluginSettingKey.Snippets.autoExpand) private var autoExpand = true
    @AppStorage(PluginSettingKey.Snippets.showSnippetHint) private var showHint = true

    var body: some View {
        Section {
            Toggle(isOn: $autoExpand) {
                SettingsRow(
                    title: "自动展开关键词",
                    subtitle: "键入片段关键词后自动替换为完整内容。",
                    icon: { SettingsRowIcon(systemImage: "text.insert") }
                )
            }

            Toggle(isOn: $showHint) {
                SettingsRow(
                    title: "显示触发提示",
                    subtitle: "在搜索结果中展示片段的触发关键词。"
                )
            }
        } header: {
            Text("展开规则")
        }
    }
}
