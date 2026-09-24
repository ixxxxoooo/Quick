// HashCalculatorSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct HashCalculatorSettingsView: View {
    @AppStorage(PluginSettingKey.HashCalculator.uppercase) private var uppercase = false
    @AppStorage(PluginSettingKey.HashCalculator.autoCopy) private var autoCopy = false

    var body: some View {
        Section {
            Toggle(isOn: $uppercase) {
                SettingsRow(
                    title: "十六进制大写显示",
                    subtitle: "输出 A-F 而非默认的小写 a-f 散列值。",
                    icon: { SettingsRowIcon(systemImage: "textformat") }
                )
            }

            Toggle(isOn: $autoCopy) {
                SettingsRow(
                    title: "计算后自动复制",
                    subtitle: "输入文本后自动把首选 SHA-256 散列结果复制到剪贴板。",
                    icon: { SettingsRowIcon(systemImage: "doc.on.clipboard") }
                )
            }
        } header: {
            Text("计算与输出")
        }
    }
}
