// UUIDGeneratorSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct UUIDGeneratorSettingsView: View {
    @AppStorage(PluginSettingKey.UUIDGenerator.uppercase) private var uppercase = true
    @AppStorage(PluginSettingKey.UUIDGenerator.removeDashes) private var removeDashes = false

    var body: some View {
        Section {
            Toggle(isOn: $uppercase) {
                SettingsRow(
                    title: "大写字母",
                    subtitle: "生成 A-F 而不是 a-f。",
                    icon: { SettingsRowIcon(systemImage: "textformat") }
                )
            }

            Toggle(isOn: $removeDashes) {
                SettingsRow(
                    title: "去掉连字符",
                    subtitle: "输出 32 位连续字符串，适合直接当数据库主键。"
                )
            }
        } header: {
            Text("生成格式")
        } footer: {
            Text("数量在插件面板里按次选择，不在这里固定。")
        }
    }
}
