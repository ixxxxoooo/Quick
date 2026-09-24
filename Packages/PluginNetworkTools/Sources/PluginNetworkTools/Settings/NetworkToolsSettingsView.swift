// NetworkToolsSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct NetworkToolsSettingsView: View {
    @AppStorage(PluginSettingKey.NetworkTools.pingCount) private var pingCount = 4
    @AppStorage(PluginSettingKey.NetworkTools.timeout) private var timeout = 5
    @AppStorage(PluginSettingKey.NetworkTools.showExternalIP) private var showExternalIP = true

    var body: some View {
        Section {
            Picker(selection: $pingCount) {
                Text("3 次").tag(3)
                Text("4 次").tag(4)
                Text("10 次").tag(10)
            } label: {
                SettingsRow(
                    title: "Ping 测试次数",
                    subtitle: "每次 Ping 测试发送的数据包数量。",
                    icon: { SettingsRowIcon(systemImage: "antenna.radiowaves.left.and.right") }
                )
            }

            Picker(selection: $timeout) {
                Text("3 秒").tag(3)
                Text("5 秒").tag(5)
                Text("10 秒").tag(10)
            } label: {
                SettingsRow(
                    title: "超时时间",
                    subtitle: "网络请求超时的等待秒数。"
                )
            }

            Toggle(isOn: $showExternalIP) {
                SettingsRow(
                    title: "显示公网 IP",
                    subtitle: "搜索网络工具时自动展示当前公网 IP。"
                )
            }
        } header: {
            Text("网络诊断")
        } footer: {
            PendingFeatureNote(detail: "Ping 测试次数与超时还没有实现：这个插件目前只做本机地址、DNS 和公网 IP，没有 ping 功能。")
        }
    }
}
