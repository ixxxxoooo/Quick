// SQLFormatterSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct SQLFormatterSettingsView: View {
    @AppStorage(PluginSettingKey.SQLFormatter.keywordCase) private var keywordCase = "uppercase"
    @AppStorage(PluginSettingKey.SQLFormatter.indent) private var indent = 2
    @AppStorage(PluginSettingKey.SQLFormatter.wrapLines) private var wrapLines = true

    var body: some View {
        Section {
            Picker(selection: $keywordCase) {
                Text("大写 (UPPERCASE)").tag("uppercase")
                Text("小写 (lowercase)").tag("lowercase")
            } label: {
                SettingsRow(
                    title: "关键字大小写",
                    subtitle: "格式化与压缩时 SELECT、FROM 等 SQL 关键字的风格。",
                    icon: { SettingsRowIcon(systemImage: "textformat") }
                )
            }

            Picker(selection: $indent) {
                Text("2 个空格").tag(2)
                Text("4 个空格").tag(4)
            } label: {
                SettingsRow(
                    title: "缩进宽度",
                    subtitle: "每层子查询、条件从句与 CASE 分支的缩进空格数。",
                    icon: { SettingsRowIcon(systemImage: "increase.indent") }
                )
            }

            Toggle(isOn: $wrapLines) {
                SettingsRow(
                    title: "自动换行",
                    subtitle: "在 SQL 编辑器中自动折行显示超长语句，关闭时横向滚动。",
                    icon: { SettingsRowIcon(systemImage: "text.wrap") }
                )
            }
        } header: {
            Text("SQL 格式化选项")
        }
    }
}
