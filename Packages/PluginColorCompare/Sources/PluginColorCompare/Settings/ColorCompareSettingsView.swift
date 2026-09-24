// ColorCompareSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 颜色工具的专属设置页
///
/// **住在插件自己的包里**：设置项的键属于 `PluginSettingKey.ColorCompare`，
/// 读写它们的人就该和它们在一起。
struct ColorCompareSettingsView: View {

    @AppStorage(PluginSettingKey.ColorCompare.defaultFormat) private var defaultFormat = "hex"
    @AppStorage(PluginSettingKey.ColorCompare.uppercaseHex) private var uppercaseHex = true

    var body: some View {
        Section {
            Picker(selection: $defaultFormat) {
                Text("十六进制 (HEX)").tag("hex")
                Text("RGB 格式").tag("rgb")
                Text("HSL 格式").tag("hsl")
            } label: {
                SettingsRow(
                    title: "默认色彩格式",
                    subtitle: "复制颜色代码时的优先格式。",
                    icon: { SettingsRowIcon(systemImage: "paintpalette") }
                )
            }

            Toggle(isOn: $uppercaseHex) {
                SettingsRow(
                    title: "HEX 字母大写",
                    subtitle: "生成 #FFFFFF 而不是小写的 #ffffff。",
                    icon: { SettingsRowIcon(systemImage: "textformat") }
                )
            }
        } header: {
            Text("颜色格式")
        }
    }
}
