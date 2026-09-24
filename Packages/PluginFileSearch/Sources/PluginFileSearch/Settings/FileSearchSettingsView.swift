// FileSearchSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct FileSearchSettingsView: View {
    @AppStorage(PluginSettingKey.FileSearch.ignoreHidden) private var ignoreHidden = true
    @AppStorage(PluginSettingKey.FileSearch.maxResults) private var maxResults = 50
    @AppStorage(PluginSettingKey.FileSearch.includeContents) private var includeContents = false

    var body: some View {
        Section {
            Toggle(isOn: $ignoreHidden) {
                SettingsRow(
                    title: "忽略隐藏文件",
                    subtitle: "不搜索以 . 开头的文件和目录。",
                    icon: { SettingsRowIcon(systemImage: "eye.slash") }
                )
            }

            Toggle(isOn: $includeContents) {
                SettingsRow(
                    title: "搜索文件内容",
                    subtitle: "同时搜索文件内的文本内容（可能较慢）。"
                )
            }

            Picker(selection: $maxResults) {
                Text("20 条").tag(20)
                Text("50 条").tag(50)
                Text("100 条").tag(100)
                Text("200 条").tag(200)
            } label: {
                SettingsRow(
                    title: "最大结果数",
                    subtitle: "单次搜索最多返回的文件数量。"
                )
            }
        } header: {
            Text("搜索规则")
        } footer: {
            Text("文件搜索基于 macOS Spotlight 索引，以「f 」或「文件 」开头触发。")
        }
    }
}
