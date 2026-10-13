// SQLFormatterSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct SQLFormatterSettingsView: View {
    @AppStorage(PluginSettingKey.SQLFormatter.keywordCase)
    private var keywordCase = SQLFormatterDefaults.keywordCase.rawValue
    @AppStorage(PluginSettingKey.SQLFormatter.indent) private var indent = SQLFormatterDefaults.indent

    var body: some View {
        Section {
            Picker(selection: $keywordCase) {
                Text("大写 (UPPERCASE)").tag(SQLKeywordCase.uppercase.rawValue)
                Text("小写 (lowercase)").tag(SQLKeywordCase.lowercase.rawValue)
            } label: {
                SettingsRow(
                    title: "关键字大小写",
                    subtitle: "格式化时 SELECT、FROM 等换行关键字的大小写风格。",
                    icon: { SettingsRowIcon(systemImage: "capslock") }
                )
            }

            Picker(selection: $indent) {
                ForEach(SQLFormatterDefaults.indentChoices, id: \.self) { width in
                    Text("\(width) 个空格").tag(width)
                }
            } label: {
                SettingsRow(
                    title: "缩进宽度",
                    subtitle: "括号内子查询的每一层，以及 AND / OR / ON / WHEN 等子句的缩进空格数。",
                    icon: { SettingsRowIcon(systemImage: "increase.indent") }
                )
            }
        } header: {
            Text("SQL 格式化选项")
        }
    }
}
