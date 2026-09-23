// CpuLoad.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一组 CPU tick（user / system / idle / nice）
struct CpuTickSample: Sendable, Equatable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    var total: UInt64 {
        UInt64(user) + UInt64(system) + UInt64(idle) + UInt64(nice)
    }
}

/// 单核占用
struct CoreUsage: Sendable, Equatable, Identifiable {
    let id: Int
    let usagePercent: Double
}

/// 由两次 tick 采样算占用率
enum CpuLoad {

    /// 整体占用率（0…100）；样本不足时返回 nil
    static func usagePercent(previous: CpuTickSample, current: CpuTickSample) -> Double? {
        let idleDelta = UInt64(current.idle) &- UInt64(previous.idle)
        let totalDelta = current.total &- previous.total
        guard totalDelta > 0 else { return nil }
        let busy = 1.0 - (Double(idleDelta) / Double(totalDelta))
        return max(0, min(100, busy * 100))
    }

    /// 每核占用；长度不一致时返回空并视为需要重新打基线
    static func perCoreUsage(previous: [CpuTickSample], current: [CpuTickSample]) -> [CoreUsage]? {
        guard previous.count == current.count, !current.isEmpty else { return nil }
        return zip(previous.indices, zip(previous, current)).compactMap { index, pair in
            guard let percent = usagePercent(previous: pair.0, current: pair.1) else { return nil }
            return CoreUsage(id: index + 1, usagePercent: percent)
        }
    }

    /// 负载均值格式化
    static func formatLoadAverage(_ values: [Double]) -> [String] {
        values.map { String(format: "%.2f", $0) }
    }
}
