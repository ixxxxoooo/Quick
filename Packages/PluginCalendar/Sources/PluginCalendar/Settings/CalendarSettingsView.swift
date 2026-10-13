// CalendarSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct CalendarSettingsView: View {
    let holidayStore: HolidayStore

    @AppStorage(PluginSettingKey.Calendar.reminderMinutes) private var reminderMinutes = 10
    @AppStorage(PluginSettingKey.Calendar.autoExtractMeetingLinks) private var autoLinks = true
    @AppStorage(PluginSettingKey.Calendar.showWeekNumber) private var showWeekNumber = false
    @AppStorage(PluginSettingKey.Calendar.showHolidays) private var showHolidays = true
    @AppStorage(PluginSettingKey.Calendar.showAlmanac) private var showAlmanac = true
    @AppStorage(PluginSettingKey.Calendar.updateHolidaysOnline) private var updateOnline = true

    @State private var checkResult: String?
    @State private var isChecking = false

    var body: some View {
        Group {
            scheduleSection
            holidaySection
        }
    }

    private var scheduleSection: some View {
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
                    subtitle: "识别腾讯会议、Zoom、Google Meet、Teams、飞书等链接，并在日程旁显示「加入会议」。",
                    icon: { SettingsRowIcon(systemImage: "video") }
                )
            }

            Toggle(isOn: $showWeekNumber) {
                SettingsRow(
                    title: "显示周数",
                    subtitle: "在月历左侧显示每行的周数，并在日期标题里标注第几周。",
                    icon: { SettingsRowIcon(systemImage: "calendar.badge.clock") }
                )
            }
        } header: {
            Text("日程与提醒")
        }
    }

    private var holidaySection: some View {
        Section {
            Toggle(isOn: $showHolidays) {
                SettingsRow(
                    title: "显示法定节假日",
                    subtitle: "月历格子标注「休」「班」（含调休补班），并显示近期假期与倒数。",
                    icon: { SettingsRowIcon(systemImage: "party.popper") }
                )
            }

            Toggle(isOn: $showAlmanac) {
                SettingsRow(
                    title: "显示黄历",
                    subtitle: "显示干支、生肖、24 节气与传统节日；关闭后月历只保留农历日期。",
                    icon: { SettingsRowIcon(systemImage: "moon.stars") }
                )
            }

            Toggle(isOn: $updateOnline) {
                SettingsRow(
                    title: "联网更新节假日",
                    subtitle: "国务院每年年底公布次年的放假安排；打开后每周自动检查一次，失败时沿用内置数据。",
                    icon: { SettingsRowIcon(systemImage: "arrow.triangle.2.circlepath") }
                )
            }

            SettingsRow(
                title: "立即检查更新",
                subtitle: checkResult ?? lastCheckText,
                icon: { SettingsRowIcon(systemImage: "arrow.clockwise") }
            ) {
                Button("检查") { check() }
                    .disabled(isChecking)
            }
        } header: {
            Text("节假日与黄历")
        } footer: {
            Text("内置 \(HolidayStoreInfo.coveredYears) 年的放假安排与 1901–2100 年的节气，离线也能用。")
        }
    }

    private var lastCheckText: String {
        guard let date = holidayStore.lastSuccess else { return "还没有联网检查过，当前使用内置数据。" }
        return "上次检查：" + date.formatted(date: .abbreviated, time: .shortened)
    }

    private func check() {
        isChecking = true
        checkResult = "正在检查…"
        Task {
            let updated = await holidayStore.refreshIfNeeded(force: true)
            isChecking = false
            checkResult = updated ? "已更新到最新的放假安排。" : "没有新的放假安排，或暂时无法连接。"
        }
    }
}

/// 设置页脚注里的数据覆盖范围，取自内置数据本身，不手写年份
private enum HolidayStoreInfo {
    static var coveredYears: String {
        let years = BundledHolidays.json.keys.sorted()
        guard let first = years.first, let last = years.last else { return "" }
        return first == last ? "\(first)" : "\(first)–\(last)"
    }
}
