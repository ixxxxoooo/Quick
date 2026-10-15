// CalculatorSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct CalculatorSettingsView: View {
    @AppStorage(PluginSettingKey.Calculator.precision) private var precision = 4
    @AppStorage(PluginSettingKey.Calculator.useGroupingSeparator) private var useGrouping = true
    @AppStorage(PluginSettingKey.Calculator.autoCopy) private var autoCopy = false
    @AppStorage(PluginSettingKey.Calculator.onlineCurrencyRates) private var onlineRates = false

    var body: some View {
        Section {
            Picker(selection: $precision) {
                Text("2 位").tag(2)
                Text("4 位").tag(4)
                Text("6 位").tag(6)
                Text("完整精度").tag(10)
            } label: {
                SettingsRow(
                    title: "小数位数",
                    subtitle: "计算结果保留的小数位数。",
                    icon: { SettingsRowIcon(systemImage: "number") }
                )
            }

            Toggle(isOn: $useGrouping) {
                SettingsRow(
                    title: "千分位分隔符",
                    subtitle: "大数字显示为 1,000,000 而不是 1000000。",
                    icon: { SettingsRowIcon(systemImage: "number") }
                )
            }

            Toggle(isOn: $autoCopy) {
                SettingsRow(
                    title: "回车后自动复制结果",
                    subtitle: "按回车确认后将计算结果自动复制到剪贴板。",
                    icon: { SettingsRowIcon(systemImage: "doc.on.clipboard") }
                )
            }

            Toggle(isOn: $onlineRates) {
                SettingsRow(
                    title: "在线更新货币汇率",
                    subtitle: "支持「100 usd to cny」「50 美元转人民币」。默认关闭；开启后每 12 小时最多从 open.er-api.com 拉取一次，关闭时只用本机缓存。",
                    icon: { SettingsRowIcon(systemImage: "arrow.triangle.2.circlepath") }
                )
            }
        } header: {
            Text("计算偏好")
        }
    }
}
