// OCRSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct OCRSettingsView: View {
    @AppStorage(PluginSettingKey.OCR.autoCopy) private var autoCopy = true
    @AppStorage(PluginSettingKey.OCR.language) private var language = "auto"

    var body: some View {
        Section {
            Picker(selection: $language) {
                Text("自动检测").tag("auto")
                Text("简体中文").tag("zh-Hans")
                Text("英语").tag("en")
                Text("日语").tag("ja")
            } label: {
                SettingsRow(
                    title: "识别语言",
                    subtitle: "优先识别的文字语言。自动检测适用于大多数场景。",
                    icon: { SettingsRowIcon(systemImage: "textformat.abc") }
                )
            }

            Toggle(isOn: $autoCopy) {
                SettingsRow(
                    title: "识别后自动复制",
                    subtitle: "OCR 完成后将识别的文字自动复制到剪贴板。"
                )
            }
        } header: {
            Text("文字识别")
        }
    }
}
