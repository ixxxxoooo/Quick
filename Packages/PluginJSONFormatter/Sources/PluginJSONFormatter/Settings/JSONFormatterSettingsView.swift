// JSONFormatterSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct JSONFormatterSettingsView: View {
    @AppStorage(PluginSettingKey.JSONFormatter.indent) private var indent = 2

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
        } header: {
            Text("格式化选项")
        } footer: {
            Text("「压缩」不受此设置影响，它总是输出单行。")
        }
    }
}

/// UUID 生成器的专属选项
