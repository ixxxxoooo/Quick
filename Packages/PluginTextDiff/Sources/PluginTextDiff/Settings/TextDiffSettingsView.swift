// TextDiffSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct TextDiffSettingsView: View {
    @AppStorage(PluginSettingKey.TextDiff.ignoreWhitespace) private var ignoreWhitespace = false
    @AppStorage(PluginSettingKey.TextDiff.ignoreCase) private var ignoreCase = false

    var body: some View {
        Section {
            Toggle(isOn: $ignoreWhitespace) {
                SettingsRow(
                    title: "忽略空白字符差异",
                    subtitle: "比对文本时忽略行首行尾空格与换行符的变动。",
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
