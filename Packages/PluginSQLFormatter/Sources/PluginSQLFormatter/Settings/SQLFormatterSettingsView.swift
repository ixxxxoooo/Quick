// SQLFormatterSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct SQLFormatterSettingsView: View {
    @AppStorage(PluginSettingKey.SQLFormatter.keywordCase) private var keywordCase = "uppercase"
    @AppStorage(PluginSettingKey.SQLFormatter.indent) private var indent = 2

    var body: some View {
        Section {
            Picker(selection: $keywordCase) {
                Text("大写 (UPPERCASE)").tag("uppercase")
                Text("小写 (lowercase)").tag("lowercase")
            } label: {
                SettingsRow(
                    title: "关键字大小写",
                    subtitle: "格式化时 SELECT、FROM 等 SQL 关键字的风格。",
                    icon: { SettingsRowIcon(systemImage: "textformat") }
                )
            }

            Picker(selection: $indent) {
                Text("2 个空格").tag(2)
                Text("4 个空格").tag(4)
            } label: {
                SettingsRow(
                    title: "缩进宽度",
                    subtitle: "每层子查询与表达式的缩进空格数。",
                    icon: { SettingsRowIcon(systemImage: "increase.indent") }
                )
            }
        } header: {
            Text("SQL 格式化选项")
        }
    }
}
