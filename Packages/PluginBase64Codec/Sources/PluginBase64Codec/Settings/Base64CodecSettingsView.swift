// Base64CodecSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct Base64CodecSettingsView: View {
    @AppStorage(PluginSettingKey.Base64Codec.urlSafe) private var urlSafe = false
    @AppStorage(PluginSettingKey.Base64Codec.wrapLines) private var wrapLines = false

    var body: some View {
        Section {
            Toggle(isOn: $urlSafe) {
                SettingsRow(
                    title: "URL 安全模式 (URL-Safe)",
                    subtitle: "将字符 +/ 替换为 -_，且省略尾部填充 =，适用于 URL 传参。",
                    icon: { SettingsRowIcon(systemImage: "shield") }
                )
            }

            Toggle(isOn: $wrapLines) {
                SettingsRow(
                    title: "自动换行",
                    subtitle: "编码长数据时每 76 个字符自动插入换行符。",
                    icon: { SettingsRowIcon(systemImage: "text.alignleft") }
                )
            }
        } header: {
            Text("编解码规则")
        }
    }
}
