// NotesSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct NotesSettingsView: View {
    @AppStorage(PluginSettingKey.Notes.autoSave) private var autoSave = true
    @AppStorage(PluginSettingKey.Notes.defaultFormat) private var defaultFormat = "plain"

    var body: some View {
        Section {
            Toggle(isOn: $autoSave) {
                SettingsRow(
                    title: "自动保存",
                    subtitle: "编辑内容时实时自动保存，无需手动操作。",
                    icon: { SettingsRowIcon(systemImage: "square.and.arrow.down") }
                )
            }

            Picker(selection: $defaultFormat) {
                Text("纯文本").tag("plain")
                Text("Markdown").tag("markdown")
            } label: {
                SettingsRow(
                    title: "默认格式",
                    subtitle: "新建笔记时的默认文本格式。"
                )
            }
        } header: {
            Text("便签存储")
        } footer: {
            PendingFeatureNote(detail: "「默认格式」还没有实现：笔记模型里没有格式字段。「自动保存」一直是开着的，关掉它也不会变成手动保存。")
        }
        .disabled(true)
    }
}
