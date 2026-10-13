// TimestampConverterSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct TimestampConverterSettingsView: View {
    @AppStorage(PluginSettingKey.TimestampConverter.defaultUnit)
    private var defaultUnit = TimestampConverterDefaults.unit.rawValue
    @AppStorage(PluginSettingKey.TimestampConverter.timeZone)
    private var timeZone = TimestampConverterDefaults.zone.rawValue

    var body: some View {
        Section {
            Picker(selection: $defaultUnit) {
                Text("秒 (10 位)").tag(TimestampUnit.seconds.rawValue)
                Text("毫秒 (13 位)").tag(TimestampUnit.milliseconds.rawValue)
            } label: {
                SettingsRow(
                    title: "默认时间戳单位",
                    subtitle: "点「填入当前」时填入的时间戳精度：秒（10 位）或毫秒（13 位）。",
                    icon: { SettingsRowIcon(systemImage: "clock") }
                )
            }

            Picker(selection: $timeZone) {
                Text("本地时区 (Local)").tag(TimestampZonePreference.local.rawValue)
                Text("协调世界时 (UTC)").tag(TimestampZonePreference.utc.rawValue)
            } label: {
                SettingsRow(
                    title: "默认时区",
                    subtitle: "结果卡片里可读时间与底部「当前时间」使用的时区；输入的无时区日期也按它解析。",
                    icon: { SettingsRowIcon(systemImage: "globe") }
                )
            }
        } header: {
            Text("转换偏好")
        }
    }
}
