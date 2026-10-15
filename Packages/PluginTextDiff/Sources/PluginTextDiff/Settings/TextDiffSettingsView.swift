// TextDiffSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct TextDiffSettingsView: View {
    @AppStorage(PluginSettingKey.TextDiff.ignoreWhitespace) private var ignoreWhitespace = false
    @AppStorage(PluginSettingKey.TextDiff.ignoreCase) private var ignoreCase = false
    @AppStorage(PluginSettingKey.TextDiff.wrapLines) private var wrapLines = false

    var body: some View {
        Section {
            Toggle(isOn: $wrapLines) {
                SettingsRow(
                    title: "自动换行",
                    subtitle: "超出编辑器宽度的长文本自动折行显示。",
                    icon: { SettingsRowIcon(systemImage: "text.wrap") }
                )
            }

            Toggle(isOn: $ignoreWhitespace) {
                SettingsRow(
                    title: "忽略空白字符差异",
                    subtitle: "忽略行首行尾空白，行内连续空白视为一个；工具栏上的开关与此同步。",
                    icon: { SettingsRowIcon(systemImage: "space") }
                )
            }

            Toggle(isOn: $ignoreCase) {
                SettingsRow(
                    title: "忽略大小写差异",
                    subtitle: "比对英文字符时不区分大写与小写。",
                    icon: { SettingsRowIcon(systemImage: "textformat.size") }
                )
            }
        } header: {
            Text("文本比对选项")
        }
    }
}
