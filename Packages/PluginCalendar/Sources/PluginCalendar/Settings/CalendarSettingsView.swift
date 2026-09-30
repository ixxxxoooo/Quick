// CalendarSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct CalendarSettingsView: View {

    let service: CalendarService

    @AppStorage(CalendarPreferences.showLunar) private var showLunar = true
    @AppStorage(CalendarPreferences.showBuiltInHolidays) private var showBuiltInHolidays = true
    @AppStorage(CalendarPreferences.showAlmanac) private var showAlmanac = true
    @AppStorage(PluginSettingKey.Calendar.showWeekNumber) private var showWeekNumber = false
    @AppStorage(CalendarPreferences.showSystemEvents) private var showSystemEvents = true
    @AppStorage(PluginSettingKey.Calendar.autoExtractMeetingLinks) private var autoLinks = true
    @AppStorage(CalendarPreferences.disabledCalendarIDs) private var disabledCalendarIDs = ""

    @State private var availableCalendars: [CalendarSource] = []

    var body: some View {
        Section {
            Toggle(isOn: $showLunar) {
                SettingsRow(
                    title: "显示农历与二十四节气",
                    subtitle: "在日历看板中显示干支生肖年、农历月日与二十四节气。",
                    icon: { SettingsRowIcon(systemImage: "moon.stars") }
                )
            }

            Toggle(isOn: $showBuiltInHolidays) {
                SettingsRow(
                    title: "显示内置中国节假日与调休",
                    subtitle: "显示内置传统/公历节日及法定「休 / 班」角标。若已启用系统订阅的节假日日历，可关闭此项或下方对应日历源以避免重复。",
                    icon: { SettingsRowIcon(systemImage: "flag") }
                )
            }

            Toggle(isOn: $showAlmanac) {
                SettingsRow(
                    title: "显示传统黄历（宜忌 / 干支 / 冲煞）",
                    subtitle: "在日视图与详情侧边栏展示每日宜忌、建除十二值神、冲煞、吉神方位与彭祖百忌。",
                    icon: { SettingsRowIcon(systemImage: "book.closed") }
                )
            }

            Toggle(isOn: $showWeekNumber) {
                SettingsRow(
                    title: "显示周数",
                    subtitle: "在月历看板顶部与网格左侧显示当前是第几周。",
                    icon: { SettingsRowIcon(systemImage: "number") }
                )
            }
        } header: {
            Text("历法与黄历显示")
        }

        Section {
            Toggle(isOn: $showSystemEvents) {
                SettingsRow(
                    title: "同步系统日历日程",
                    subtitle: "读取 macOS「日历」应用中的日程安排并在看板中显示事件圆点与详情。",
                    icon: { SettingsRowIcon(systemImage: "calendar") }
                )
            }

            if showSystemEvents {
                Toggle(isOn: $autoLinks) {
                    SettingsRow(
                        title: "提取会议链接",
                        subtitle: "自动识别日程中的腾讯会议、飞书、Zoom、Google Meet 等在线会议链接并显示快捷加入按钮。",
                        icon: { SettingsRowIcon(systemImage: "video") }
                    )
                }

                ForEach(availableCalendars) { source in
                    Toggle(isOn: calendarBinding(for: source.id)) {
                        SettingsRow(
                            title: source.title,
                            subtitle: source.isSubscriptionOrHoliday
                                ? "系统订阅 / 节假日日历（如与内置节假日重复可取消勾选）"
                                : "系统日历源",
                            icon: {
                                SettingsRowIcon(
                                    systemImage: source.isSubscriptionOrHoliday
                                        ? "calendar.badge.clock"
                                        : "calendar.circle"
                                )
                            }
                        )
                    }
                }
            }
        } header: {
            Text("系统日历与日程源")
        }
        .onAppear {
            service.refreshAuthorizationStatus()
            availableCalendars = service.availableCalendars()
        }
        .onChange(of: service.changeToken) { _, _ in
            availableCalendars = service.availableCalendars()
        }
    }

    private func calendarBinding(for calendarID: String) -> Binding<Bool> {
        Binding(
            get: {
                let disabled = CalendarPreferences.disabledIDs(from: disabledCalendarIDs)
                return !disabled.contains(calendarID)
            },
            set: { isEnabled in
                var disabled = CalendarPreferences.disabledIDs(from: disabledCalendarIDs)
                if isEnabled {
                    disabled.remove(calendarID)
                } else {
                    disabled.insert(calendarID)
                }
                disabledCalendarIDs = CalendarPreferences.encodedDisabledIDs(disabled)
            }
        )
    }
}
