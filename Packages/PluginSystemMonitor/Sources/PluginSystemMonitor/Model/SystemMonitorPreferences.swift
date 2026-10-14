// SystemMonitorPreferences.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 系统监控偏好：默认标签与 CPU / 内存 / 磁盘的显示口径
///
/// 纯映射，不碰 UI；非法存储值一律回落到与设置页默认项一致的安全值。
enum SystemMonitorPreferences {

    static let defaultTab = SystemMonitorTab.systemInfo
    /// CPU / 内存 / 磁盘共用的默认口径
    static let defaultMode = UsageDisplayMode.used
    /// 电池没有「已用」的直观含义，固定显示剩余电量
    static let batteryMode = UsageDisplayMode.free

    static func tab(storedValue: String?) -> SystemMonitorTab {
        guard let storedValue, let tab = SystemMonitorTab(rawValue: storedValue) else {
            return defaultTab
        }
        return tab
    }

    static func displayMode(storedValue: String?, fallback: UsageDisplayMode) -> UsageDisplayMode {
        guard let storedValue, let mode = UsageDisplayMode(rawValue: storedValue) else {
            return fallback
        }
        return mode
    }

    static func configuredTab(defaults: UserDefaults = .standard) -> SystemMonitorTab {
        tab(storedValue: defaults.string(forKey: PluginSettingKey.SystemMonitor.defaultTab))
    }

    static func configuredMode(defaults: UserDefaults = .standard) -> UsageDisplayMode {
        displayMode(
            storedValue: defaults.string(forKey: PluginSettingKey.SystemMonitor.displayMode),
            fallback: defaultMode
        )
    }
}
