// JSONFormatterSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct JSONFormatterSettingsView: View {
    @AppStorage(PluginSettingKey.JSONFormatter.indent) private var indent = 2
    @AppStorage(PluginSettingKey.JSONFormatter.wrapLines) private var wrapLines = true

    var body: some View {
        Section {
            Picker(selection: $indent) {
                Text("2 个空格").tag(2)
                Text("4 个空格").tag(4)
            } label: {
                SettingsRow(
                    title: "缩进风格",
                    subtitle: "格式化 JSON 时的缩进宽度。",
                    icon: { SettingsRowIcon(systemImage: "curlybraces") }
                )
            }

            Toggle(isOn: $wrapLines) {
                SettingsRow(
                    title: "自动换行",
                    subtitle: "在 JSON 代码编辑器中自动折行显示超长内容，关闭时横向滚动。",
                    icon: { SettingsRowIcon(systemImage: "text.wrap") }
                )
            }
        } header: {
            Text("格式化选项")
        } footer: {
            Text("「压缩」不受缩进设置影响，它总是输出单行。")
        }
    }
}
