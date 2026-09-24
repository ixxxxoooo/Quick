// CalendarSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct CalendarSettingsView: View {
    @AppStorage(PluginSettingKey.Calendar.reminderMinutes) private var reminderMinutes = 10
    @AppStorage(PluginSettingKey.Calendar.autoExtractMeetingLinks) private var autoLinks = true
    @AppStorage(PluginSettingKey.Calendar.showWeekNumber) private var showWeekNumber = false

    var body: some View {
        Section {
            Picker(selection: $reminderMinutes) {
                Text("5 分钟").tag(5)
                Text("10 分钟").tag(10)
                Text("15 分钟").tag(15)
                Text("30 分钟").tag(30)
            } label: {
                SettingsRow(
                    title: "提前提醒时间",
                    subtitle: "在日程开始前多久发出通知。",
                    icon: { SettingsRowIcon(systemImage: "bell") }
                )
            }

            Toggle(isOn: $autoLinks) {
                SettingsRow(
                    title: "提取会议链接",
                    subtitle: "自动识别腾讯会议、Zoom、Google Meet 等会议链接。"
                )
            }

            Toggle(isOn: $showWeekNumber) {
                SettingsRow(
                    title: "显示周数",
                    subtitle: "在日历视图中显示当前是第几周。"
                )
            }
        } header: {
            Text("日程与提醒")
        } footer: {
            PendingFeatureNote(detail: "这三项还没有实现：EventKit 只用来读日程，提醒、会议链接提取和周数都还没有接上。")
        }
        .disabled(true)
    }
}
