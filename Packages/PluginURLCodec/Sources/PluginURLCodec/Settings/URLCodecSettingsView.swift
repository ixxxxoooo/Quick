// URLCodecSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct URLCodecSettingsView: View {
    @AppStorage(PluginSettingKey.URLCodec.encodeSpacesAsPluses) private var spacesAsPluses = false
    @AppStorage(PluginSettingKey.URLCodec.encodeFullUrl) private var encodeFullUrl = false

    var body: some View {
        Section {
            Toggle(isOn: $spacesAsPluses) {
                SettingsRow(
                    title: "空格编码为加号 (+)",
                    subtitle: "关闭时使用标准的 %20，开启后符合 application/x-www-form-urlencoded 规范。",
                    icon: { SettingsRowIcon(systemImage: "plus") }
                )
            }

            Toggle(isOn: $encodeFullUrl) {
                SettingsRow(
                    title: "完整 URL 模式",
                    subtitle: "保留 :// 等协议分隔符，仅对查询参数与路径非保留字符编码。",
                    icon: { SettingsRowIcon(systemImage: "link") }
                )
            }
        } header: {
            Text("URL 编码选项")
        }
    }
}
