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
                Text("不提醒").tag(0)
                Text("5 分钟").tag(5)
                Text("10 分钟").tag(10)
                Text("15 分钟").tag(15)
                Text("30 分钟").tag(30)
            } label: {
                SettingsRow(
                    title: "提前提醒时间",
                    subtitle: "在日程开始前多久发出系统通知；全天事件不提醒。首次有提醒要发时会询问通知权限。",
                    icon: { SettingsRowIcon(systemImage: "bell") }
                )
            }

            Toggle(isOn: $autoLinks) {
                SettingsRow(
                    title: "提取会议链接",
                    subtitle: "识别腾讯会议、Zoom、Google Meet、Teams、飞书等链接，并在日程旁显示「加入会议」。"
                )
            }

            Toggle(isOn: $showWeekNumber) {
                SettingsRow(
                    title: "显示周数",
                    subtitle: "在月历左侧显示每行的周数，并在日期标题里标注第几周。"
                )
            }
        } header: {
            Text("日程与提醒")
        }
    }
}
