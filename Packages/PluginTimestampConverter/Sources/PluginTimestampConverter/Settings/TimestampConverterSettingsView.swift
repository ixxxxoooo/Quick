// TimestampConverterSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct TimestampConverterSettingsView: View {
    @AppStorage(PluginSettingKey.TimestampConverter.defaultUnit) private var defaultUnit = "seconds"
    @AppStorage(PluginSettingKey.TimestampConverter.timeZone) private var timeZone = "local"

    var body: some View {
        Section {
            Picker(selection: $defaultUnit) {
                Text("秒 (10 位)").tag("seconds")
                Text("毫秒 (13 位)").tag("milliseconds")
            } label: {
                SettingsRow(
                    title: "默认时间戳单位",
                    subtitle: "生成当前时间戳时使用的默认精度单位。",
                    icon: { SettingsRowIcon(systemImage: "clock") }
                )
            }

            Picker(selection: $timeZone) {
                Text("本地时区 (Local)").tag("local")
                Text("协调世界时 (UTC)").tag("utc")
            } label: {
                SettingsRow(
                    title: "默认时区",
                    subtitle: "格式化输出可读日期文本时使用的参考时区。",
                    icon: { SettingsRowIcon(systemImage: "globe") }
                )
            }
        } header: {
            Text("转换偏好")
        }
    }
}
