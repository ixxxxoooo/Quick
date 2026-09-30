// CalendarSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct CalendarSettingsView: View {
    @AppStorage(PluginSettingKey.Calendar.autoExtractMeetingLinks) private var autoLinks = true
    @AppStorage(PluginSettingKey.Calendar.showWeekNumber) private var showWeekNumber = false

    var body: some View {
        Section {
            Toggle(isOn: $showWeekNumber) {
                SettingsRow(
                    title: "显示周数",
                    subtitle: "在月历看板顶部与网格左侧显示当前是第几周。",
                    icon: { SettingsRowIcon(systemImage: "number") }
                )
            }

            Toggle(isOn: $autoLinks) {
                SettingsRow(
                    title: "提取会议链接",
                    subtitle: "自动识别日程中的腾讯会议、飞书、Zoom、Google Meet 等在线会议链接并显示快捷加入按钮。",
                    icon: { SettingsRowIcon(systemImage: "video") }
                )
            }
        } header: {
            Text("日历看板与日程")
        }
    }
}
