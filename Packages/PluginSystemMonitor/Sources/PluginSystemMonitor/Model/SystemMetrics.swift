// SystemMetrics.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 系统信息的展示格式化
///
/// 阈值、单位、四舍五入都是纯计算，抽出来才能把边界（24 小时、1024 字节）钉死；
/// `ProcessScanner` 只负责把 `Foundation.ProcessInfo` 的数字喂进来。
enum SystemMetrics {

    private static let secondsPerHour = 3600
    private static let secondsPerMinute = 60
    private static let hoursPerDay = 24

    /// 按 1024 进制换算，所以标的是 GB 实际是 GiB —— 和「活动监视器」的口径一致
    private static let bytesPerGigabyte = 1_073_741_824.0

    /// 运行时间
    ///
    /// 判据是「超过 24 小时」而不是「满 24 小时」：恰好 24 小时仍显示为小时，
    /// 满 25 小时才换成「天 + 小时」，并且换过去之后不再显示分钟。
    /// 低于 1 小时只显示「0 小时 N 分钟」。
    static func uptime(_ seconds: TimeInterval) -> String {
        let totalHours = Int(seconds) / secondsPerHour
        let minutes = (Int(seconds) % secondsPerHour) / secondsPerMinute

        if totalHours > hoursPerDay {
            return "\(totalHours / hoursPerDay) 天 \(totalHours % hoursPerDay) 小时"
        }
        return "\(totalHours) 小时 \(minutes) 分钟"
    }

    /// 内存总量
    ///
    /// 只保留一位小数，所以不足约 0.05 GB 的输入会显示成 "0.0 GB"。
    static func bytes(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / bytesPerGigabyte)
    }
}
