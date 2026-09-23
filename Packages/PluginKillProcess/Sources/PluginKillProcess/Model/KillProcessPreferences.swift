// KillProcessPreferences.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 结束进程偏好
enum KillProcessPreferences {

    static let defaultSort = KillProcessSortMode.cpu
    static let defaultInterval = 3
    static let intervalChoices = [1, 2, 3, 5, 10]

    static func sort(storedValue: String?) -> KillProcessSortMode {
        guard let storedValue, let mode = KillProcessSortMode(rawValue: storedValue) else {
            return defaultSort
        }
        return mode
    }

    static func interval(storedValue: Int) -> Int {
        intervalChoices.contains(storedValue) ? storedValue : defaultInterval
    }

    static func configuredSort(defaults: UserDefaults = .standard) -> KillProcessSortMode {
        sort(storedValue: defaults.string(forKey: PluginSettingKey.KillProcess.sortMode))
    }

    static func configuredInterval(defaults: UserDefaults = .standard) -> Int {
        interval(storedValue: defaults.integer(forKey: PluginSettingKey.KillProcess.refreshInterval))
    }

    static func showPID(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: PluginSettingKey.KillProcess.showPID) as? Bool ?? false
    }

    static func searchInPath(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: PluginSettingKey.KillProcess.searchInPath) as? Bool ?? false
    }

    static func searchInPID(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: PluginSettingKey.KillProcess.searchInPID) as? Bool ?? false
    }
}
