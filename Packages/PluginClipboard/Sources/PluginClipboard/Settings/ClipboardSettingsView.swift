// ClipboardSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct ClipboardSettingsView: View {
    @AppStorage(PluginSettingKey.Clipboard.maxEntries) private var maxEntries = 500
    /// 图片预算以 MB 为单位给用户选，存储层用的是字节
    @AppStorage(PluginSettingKey.Clipboard.imageByteBudget) private var imageBudgetBytes = 256 * 1024 * 1024

    private var imageBudgetMB: Binding<Int> {
        Binding(
            get: { imageBudgetBytes / (1024 * 1024) },
            set: { imageBudgetBytes = $0 * 1024 * 1024 }
        )
    }
    @AppStorage(PluginSettingKey.Clipboard.clearOnQuit) private var clearOnQuit = false
    @AppStorage(PluginSettingKey.Clipboard.monitorEnabled) private var monitorEnabled = true
    @AppStorage(PluginSettingKey.Clipboard.showPreview) private var showPreview = true
    @AppStorage(PluginSettingKey.Clipboard.deduplication) private var deduplication = true

    var body: some View {
        Section {
            Toggle(isOn: $monitorEnabled) {
                SettingsRow(
                    title: "启用剪贴板监听",
                    subtitle: "实时监控系统剪贴板变化并记录历史。关闭后不再自动捕获。",
                    icon: { SettingsRowIcon(systemImage: "eye") }
                )
            }
        } header: {
            Text("监听")
        }

        Section {
            SettingsRow(
                title: "历史记录上限",
                subtitle: "超过上限时自动淘汰最旧的条目。置顶与收藏的条目不受影响。",
                icon: { SettingsRowIcon(systemImage: "tray.full") }
            ) {
                Stepper("\(maxEntries) 条", value: $maxEntries, in: 100...5000, step: 100)
                    .frame(width: 120)
            }

            SettingsRow(
                title: "图片占用上限",
                subtitle: "图片比文字大得多，只限条数挡不住。超出后从最旧的图片开始删。",
                icon: { SettingsRowIcon(systemImage: "photo.stack") }
            ) {
                Picker("", selection: imageBudgetMB) {
                    Text("64 MB").tag(64)
                    Text("128 MB").tag(128)
                    Text("256 MB").tag(256)
                    Text("512 MB").tag(512)
                }
                .labelsHidden()
                .frame(width: 120)
            }

            Toggle(isOn: $deduplication) {
                SettingsRow(
                    title: "自动去重",
                    subtitle: "连续复制相同内容时只保留一条记录。"
                )
            }

            Toggle(isOn: $showPreview) {
                SettingsRow(
                    title: "显示内容预览",
                    subtitle: "在搜索结果中展示剪贴板内容的前几行。"
                )
            }
        } header: {
            Text("历史记录")
        }

        Section {
            Toggle(isOn: $clearOnQuit) {
                SettingsRow(
                    title: "退出时清除历史",
                    subtitle: "关闭 Quick 时自动清空剪贴板历史。适合注重隐私的用户。",
                    icon: { SettingsRowIcon(systemImage: "trash") }
                )
            }
        } header: {
            Text("隐私")
        }
    }
}
