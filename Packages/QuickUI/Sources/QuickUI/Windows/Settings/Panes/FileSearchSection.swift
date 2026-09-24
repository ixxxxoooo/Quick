// FileSearchSection.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickPlatform
import SwiftUI

/// 文件搜索的设置分区
///
/// 文件搜索是宿主能力而不是插件（见 `docs/features.md`），所以它的设置项挂在「搜索」页，
/// 与应用索引目录同屏 —— 两者都决定「主搜索能搜到什么」。
struct FileSearchSection: View {

    @AppStorage(SettingsKey.fileSearchMaxResults)
    private var maxResults = FileSearchPreferences.defaultMaxResults

    @AppStorage(SettingsKey.fileSearchIgnoreHidden)
    private var ignoreHidden = true

    @AppStorage(SettingsKey.fileSearchIncludeContents)
    private var includeContents = false

    var body: some View {
        Section {
            SettingsRow(
                title: "结果上限",
                subtitle: "一次搜索最多返回多少个文件。",
                icon: { SettingsRowIcon(systemImage: "list.number") }
            ) {
                Picker("", selection: $maxResults) {
                    ForEach(FileSearchPreferences.resultChoices, id: \.self) { choice in
                        Text("\(choice) 条").tag(choice)
                    }
                }
                .labelsHidden()
                .frame(width: DesignTokens.Size.settingsControl)
            }

            Toggle(isOn: $ignoreHidden) {
                SettingsRow(
                    title: "忽略隐藏文件",
                    subtitle: "不返回以 . 开头的文件，也不返回藏在隐藏目录里的文件。",
                    icon: { SettingsRowIcon(systemImage: "eye.slash") }
                )
            }

            Toggle(isOn: $includeContents) {
                SettingsRow(
                    title: "搜索文件内容",
                    subtitle: "除了文件名，还在文件正文里匹配关键词。范围更大，也会更慢。",
                    icon: { SettingsRowIcon(systemImage: "doc.text.magnifyingglass") }
                )
            }
        } header: {
            Text("文件搜索")
        } footer: {
            Text("在主面板输入 f 加空格再加关键词（也支持 file / 文件）即可搜索文件，结果直接出现在搜索结果里。")
        }
    }
}
