// HardwareCache.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 硬件规格的跨启动缓存
///
/// 硬件几乎不变，没必要每次启动都重新采集（GPU 那一步尤其慢）。首次采到后写进
/// `UserDefaults`，下次启动先拿缓存秒开，再在后台刷新。`v1` 是结构版本 ——
/// 字段增删时改它，老缓存自然失效，不会解出半截数据。
enum HardwareCache {

    private static let key = "sysmonitor.hardware.cache.v1"

    static func load(defaults: UserDefaults = .standard) -> HardwareInfo? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HardwareInfo.self, from: data)
    }

    static func save(_ info: HardwareInfo?, defaults: UserDefaults = .standard) {
        guard let info, let data = try? JSONEncoder().encode(info) else { return }
        defaults.set(data, forKey: key)
    }
}
