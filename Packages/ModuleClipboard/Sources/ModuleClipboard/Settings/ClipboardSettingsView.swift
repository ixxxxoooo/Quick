// ClipboardSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// 剪贴板模块设置视图
struct ClipboardSettingsView: View {

    @AppStorage("clipboard.maxEntries") private var maxEntries = 500
    @AppStorage("clipboard.monitorEnabled") private var monitorEnabled = true

    var body: some View {
        Form {
            Toggle("启用剪贴板监听", isOn: $monitorEnabled)

            Stepper("最大保存条目：\(maxEntries)", value: $maxEntries, in: 100...2000, step: 100)
        }
        .formStyle(.grouped)
        .padding()
    }
}
