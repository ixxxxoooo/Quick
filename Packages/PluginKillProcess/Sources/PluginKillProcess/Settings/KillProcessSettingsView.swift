// KillProcessSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct KillProcessSettingsView: View {
    @AppStorage(PluginSettingKey.KillProcess.sortMode) private var sortMode = "cpu"
    @AppStorage(PluginSettingKey.KillProcess.refreshInterval) private var refreshInterval = 3
    @AppStorage(PluginSettingKey.KillProcess.showPID) private var showPID = false
    @AppStorage(PluginSettingKey.KillProcess.searchInPath) private var searchInPath = false
    @AppStorage(PluginSettingKey.KillProcess.searchInPID) private var searchInPID = false

    var body: some View {
        Section {
            Picker(selection: $sortMode) {
                Text("CPU").tag("cpu")
                Text("内存").tag("memory")
            } label: {
                SettingsRow(
                    title: "默认排序",
                    subtitle: "打开结束进程时按 CPU 或内存占用排序。",
                    icon: { SettingsRowIcon(systemImage: "arrow.up.arrow.down") }
                )
            }

            Picker(selection: $refreshInterval) {
                Text("1 秒").tag(1)
                Text("2 秒").tag(2)
                Text("3 秒").tag(3)
                Text("5 秒").tag(5)
                Text("10 秒").tag(10)
            } label: {
                SettingsRow(
                    title: "刷新周期",
                    subtitle: "进程列表的自动刷新间隔。",
                    icon: { SettingsRowIcon(systemImage: "timer") }
                )
            }

            Toggle(isOn: $showPID) {
                SettingsRow(
                    title: "显示 PID",
                    subtitle: "在进程名下方显示进程号。"
                )
            }

            Toggle(isOn: $searchInPath) {
                SettingsRow(
                    title: "搜索可执行路径",
                    subtitle: "标题栏搜索时同时匹配完整路径。"
                )
            }

            Toggle(isOn: $searchInPID) {
                SettingsRow(
                    title: "搜索 PID",
                    subtitle: "标题栏搜索时同时匹配进程号。"
                )
            }
        } header: {
            Text("配置")
        }
    }
}
