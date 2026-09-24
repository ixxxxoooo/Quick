// ScreenshotSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct ScreenshotSettingsView: View {
    @AppStorage(PluginSettingKey.Screenshot.format) private var format = "png"
    @AppStorage(PluginSettingKey.Screenshot.saveToDesktop) private var saveToDesktop = true

    var body: some View {
        Section {
            Picker(selection: $format) {
                Text("PNG（无损）").tag("png")
                Text("JPEG（紧凑）").tag("jpeg")
                Text("HEIC（高效）").tag("heic")
            } label: {
                SettingsRow(
                    title: "图片格式",
                    subtitle: "截图保存使用的图片编码格式。",
                    icon: { SettingsRowIcon(systemImage: "photo") }
                )
            }

            Toggle(isOn: $saveToDesktop) {
                SettingsRow(
                    title: "保存到桌面",
                    subtitle: "截图自动保存到桌面，否则仅复制到剪贴板。"
                )
            }
        } header: {
            Text("截图设置")
        }
    }
}

// MARK: - 独立开发者工具设置子表单
