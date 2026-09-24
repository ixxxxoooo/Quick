// SystemMonitorSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct SystemMonitorSettingsView: View {
    @AppStorage(PluginSettingKey.SystemMonitor.interval) private var interval = 2
    @AppStorage(PluginSettingKey.SystemMonitor.defaultTab) private var defaultTab = "system-info"
    @AppStorage(PluginSettingKey.SystemMonitor.displayModeCPU) private var cpuMode = "used"
    @AppStorage(PluginSettingKey.SystemMonitor.displayModeMemory) private var memoryMode = "used"
    @AppStorage(PluginSettingKey.SystemMonitor.displayModeDisk) private var diskMode = "free"
    @AppStorage(PluginSettingKey.SystemMonitor.displayModeBattery) private var batteryMode = "free"
    @AppStorage(PluginSettingKey.SystemMonitor.showMenuBarStats) private var showMenuBar = false

    var body: some View {
        Section {
            Picker(selection: $defaultTab) {
                Text("系统信息").tag("system-info")
                Text("CPU").tag("cpu")
                Text("内存").tag("memory")
                Text("磁盘").tag("disk")
                Text("电源").tag("power")
                Text("网络").tag("network")
                Text("温度").tag("temperature")
            } label: {
                SettingsRow(
                    title: "默认标签",
                    subtitle: "打开系统监控时默认选中的视图。",
                    icon: { SettingsRowIcon(systemImage: "rectangle.split.2x1") }
                )
            }

            Picker(selection: $cpuMode) {
                Text("显示已用").tag("used")
                Text("显示空闲").tag("free")
            } label: {
                SettingsRow(
                    title: "CPU 显示模式",
                    subtitle: "侧栏与详情里的 CPU 百分比按已用或空闲展示。",
                    icon: { SettingsRowIcon(systemImage: "cpu") }
                )
            }

            Picker(selection: $memoryMode) {
                Text("显示已用").tag("used")
                Text("显示空闲").tag("free")
            } label: {
                SettingsRow(
                    title: "内存显示模式",
                    subtitle: "侧栏与详情里的内存百分比按已用或空闲展示。"
                )
            }

            Picker(selection: $diskMode) {
                Text("显示已用").tag("used")
                Text("显示空闲").tag("free")
            } label: {
                SettingsRow(
                    title: "磁盘显示模式",
                    subtitle: "侧栏与详情里的磁盘百分比按已用或空闲展示。"
                )
            }

            Picker(selection: $batteryMode) {
                Text("显示已用").tag("used")
                Text("显示空闲").tag("free")
            } label: {
                SettingsRow(
                    title: "电池显示模式",
                    subtitle: "有内置电池时，按剩余或已用展示电量。"
                )
            }

            Picker(selection: $interval) {
                Text("1 秒").tag(1)
                Text("2 秒").tag(2)
                Text("5 秒").tag(5)
                Text("10 秒").tag(10)
            } label: {
                SettingsRow(
                    title: "刷新周期",
                    subtitle: "系统数据的采样间隔。更短的间隔更实时，但消耗更多资源。",
                    icon: { SettingsRowIcon(systemImage: "timer") }
                )
            }

            Toggle(isOn: $showMenuBar) {
                SettingsRow(
                    title: "菜单栏显示 CPU/内存",
                    subtitle: "在菜单栏图标旁实时展示系统负载。"
                )
            }
            .disabled(true)
        } header: {
            Text("配置")
        } footer: {
            PendingFeatureNote(detail: "「菜单栏显示 CPU/内存」还没有实现：面板内采样已就绪，菜单栏文案尚未接线。")
        }
    }
}
