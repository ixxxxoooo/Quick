// SystemMonitorTab.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 系统监控面板的视图分类
///
/// 与 Raycast System Monitor 的侧栏条目一一对应；`rawValue` 同时是设置页「默认标签」的存储值。
enum SystemMonitorTab: String, CaseIterable, Identifiable, Sendable {
    case systemInfo = "system-info"
    case cpu = "cpu"
    case memory = "memory"
    case disk = "disk"
    case power = "power"
    case network = "network"
    case temperature = "temperature"

    var id: String { rawValue }

    /// 侧栏标题
    var title: String {
        switch self {
        case .systemInfo: "系统信息"
        case .cpu: "CPU"
        case .memory: "内存"
        case .disk: "磁盘"
        case .power: "电源"
        case .network: "网络"
        case .temperature: "温度"
        }
    }

    /// SF Symbol
    var icon: String {
        switch self {
        case .systemInfo: "desktopcomputer"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .power: "battery.100"
        case .network: "network"
        case .temperature: "thermometer.medium"
        }
    }

    /// 设置页「默认标签」下拉里的文案
    var settingsLabel: String {
        title
    }
}

/// 占用率显示口径：已用 / 空闲
///
/// 侧栏与详情里的百分比会按这个口径翻转（例如 CPU 空闲模式显示 `100 - used`）。
enum UsageDisplayMode: String, CaseIterable, Sendable {
    case used
    case free

    var settingsLabel: String {
        switch self {
        case .used: "显示已用"
        case .free: "显示空闲"
        }
    }
}
