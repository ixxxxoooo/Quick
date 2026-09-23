// SystemMonitorPreferences.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 系统监控偏好：默认标签与各模块的显示口径
///
/// 纯映射，不碰 UI；非法存储值一律回落到与设置页默认项一致的安全值。
enum SystemMonitorPreferences {

    static let defaultTab = SystemMonitorTab.systemInfo
    static let defaultCPUMode = UsageDisplayMode.used
    static let defaultMemoryMode = UsageDisplayMode.used
    static let defaultDiskMode = UsageDisplayMode.free
    static let defaultBatteryMode = UsageDisplayMode.free

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

    static func configuredCPUMode(defaults: UserDefaults = .standard) -> UsageDisplayMode {
        displayMode(
            storedValue: defaults.string(forKey: PluginSettingKey.SystemMonitor.displayModeCPU),
            fallback: defaultCPUMode
        )
    }

    static func configuredMemoryMode(defaults: UserDefaults = .standard) -> UsageDisplayMode {
        displayMode(
            storedValue: defaults.string(forKey: PluginSettingKey.SystemMonitor.displayModeMemory),
            fallback: defaultMemoryMode
        )
    }

    static func configuredDiskMode(defaults: UserDefaults = .standard) -> UsageDisplayMode {
        displayMode(
            storedValue: defaults.string(forKey: PluginSettingKey.SystemMonitor.displayModeDisk),
            fallback: defaultDiskMode
        )
    }

    static func configuredBatteryMode(defaults: UserDefaults = .standard) -> UsageDisplayMode {
        displayMode(
            storedValue: defaults.string(forKey: PluginSettingKey.SystemMonitor.displayModeBattery),
            fallback: defaultBatteryMode
        )
    }
}
