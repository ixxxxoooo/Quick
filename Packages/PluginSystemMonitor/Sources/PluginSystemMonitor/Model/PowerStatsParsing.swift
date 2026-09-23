// PowerStatsParsing.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 电源 / 电池快照
struct PowerSnapshot: Sendable, Equatable {
    /// 是否存在可报告的电池（台式无电池时为 false）
    let hasBattery: Bool
    /// 0…100；无电池时为 nil
    let batteryPercent: Int?
    let isCharging: Bool
    let isOnACPower: Bool
    let condition: String
    let cycleCount: String
    let timeRemainingMinutes: Int?

    /// 侧栏摘要
    var sidebarSummary: String {
        guard hasBattery, let batteryPercent else { return "N/A" }
        return SystemMetrics.percent(Double(batteryPercent))
    }
}

/// 解析 `pmset -g batt` / `ioreg` 相关文本
enum PowerStatsParsing {

    /// 从 `pmset -g batt` 判断是否有电池并读出百分比与电源状态
    static func parsePmset(
        _ output: String
    ) -> (hasBattery: Bool, percent: Int?, isCharging: Bool, isOnAC: Bool) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (false, nil, false, true)
        }

        // 仅 AC、完全没有 InternalBattery 行 → 台式机
        let hasBatteryLine = trimmed.contains("InternalBattery")
        let isOnAC = trimmed.contains("AC Power") || trimmed.contains("AC attached")
        let isCharging =
            trimmed.localizedCaseInsensitiveContains("charging")
            && !trimmed.localizedCaseInsensitiveContains("not charging")

        guard hasBatteryLine else {
            // 台式机没有电池，必然接通电源。不能写成 `isOnAC || true`：那是恒真表达式，
            // 真实意图是「无电池 = 一定在用交流电」—— 部分机型/UPS 的 pmset 输出
            // 可能不含 "AC Power" 字样
            return (false, nil, false, true)
        }

        let percent: Int?
        if let match = trimmed.firstMatch(of: /(\d+)%/) {
            percent = Int(match.1)
        } else {
            percent = nil
        }

        return (true, percent, isCharging, isOnAC)
    }

    /// 按显示口径格式化电量
    static func displayedLevel(_ percent: Int?, mode: UsageDisplayMode) -> String {
        guard let percent else { return "N/A" }
        let value = mode == .free ? percent : max(0, 100 - percent)
        return SystemMetrics.percent(Double(value))
    }
}
