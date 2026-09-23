// SystemMetrics.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 系统信息的展示格式化与压力色阶
///
/// 频率、单位、四舍五入都是纯计算，抽出来才能把边界（24 小时、1024 字节）钉死；
/// 采集层只负责把环境事实喂进来。
enum SystemMetrics {

    private static let secondsPerHour = 3600
    private static let secondsPerMinute = 60
    private static let hoursPerDay = 24

    /// 按 1024 进制换算，所以标的是 GB 实际是 GiB —— 和「活动监视器」的口径一致
    private static let bytesPerGigabyte = 1_073_741_824.0
    private static let bytesPerMegabyte = 1_048_576.0
    private static let kilobytesPerMegabyte = 1024.0

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

    /// 内存总量（GiB，一位小数）
    static func bytes(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / bytesPerGigabyte)
    }

    /// 兆字节 → 「X.X GB」展示（Raycast 内存明细口径）
    static func megabytesAsGigabytes(_ megabytes: Double) -> String {
        String(format: "%.1f GB", megabytes / kilobytesPerMegabyte)
    }

    /// 整数兆字节展示
    static func megabytes(_ megabytes: Double) -> String {
        "\(Int(megabytes.rounded())) MB"
    }

    /// `ps` 的 RSS（KB）→ 人类可读
    static func rssKilobytes(_ kilobytes: Int) -> String {
        if kilobytes >= 1024 * 1024 {
            return String(
                format: "%.1f GB", Double(kilobytes) / (kilobytesPerMegabyte * kilobytesPerMegabyte))
        }
        if kilobytes >= 1024 {
            return "\(Int((Double(kilobytes) / kilobytesPerMegabyte).rounded())) MB"
        }
        return "\(kilobytes) KB"
    }

    /// 百分比整数展示，带空格与百分号（对齐 Raycast 侧栏）
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded())) %"
    }

    /// 按显示口径翻转占用率：空闲模式显示 `100 - used`
    static func displayedPercent(used: Double, mode: UsageDisplayMode) -> Double {
        switch mode {
        case .used: used
        case .free: max(0, 100 - used)
        }
    }

    /// 侧栏百分比文案；磁盘的 free 模式追加 " free"
    static func accessoryPercent(
        used: Double,
        mode: UsageDisplayMode,
        suffixWhenFree: String? = nil
    ) -> String {
        let displayed = displayedPercent(used: used, mode: mode)
        let base = percent(displayed)
        if mode == .free, let suffixWhenFree {
            return "\(base)\(suffixWhenFree)"
        }
        return base
    }

    /// 内存压力等级文案（中文）
    static func pressureLabel(_ level: Int) -> String {
        switch level {
        case 1: "正常"
        case 2: "警告"
        case 3: "紧急"
        case 4: "危急"
        default: "未知"
        }
    }

    /// 资源压力色阶：数字越大越紧张
    ///
    /// 阈值对齐 Raycast `colorForPressurePercent`：≥90 红、≥80 橙、≥60 黄档（用 progress）、其余绿。
    enum PressureTone: Sendable, Equatable {
        case normal
        case elevated
        case warning
        case critical
        case muted
    }

    /// 把「当前展示出来的百分比」换算成压力（空闲口径下压力 = 100 - 展示值）
    static func pressure(fromDisplayed displayed: Double, mode: UsageDisplayMode) -> Double {
        mode == .free ? 100 - displayed : displayed
    }

    static func tone(forPressure pressure: Double) -> PressureTone {
        if pressure >= 90 { return .critical }
        if pressure >= 80 { return .warning }
        if pressure >= 60 { return .elevated }
        return .normal
    }

    static func tone(forPercentText text: String, mode: UsageDisplayMode) -> PressureTone {
        guard
            let value = Double(
                text.split(separator: " ").first ?? Substring(text.replacingOccurrences(of: "%", with: "")))
        else {
            return .muted
        }
        return tone(forPressure: pressure(fromDisplayed: value, mode: mode))
    }

    static func tone(forPressureLabel label: String) -> PressureTone {
        switch label {
        case "正常": .normal
        case "警告": .warning
        case "紧急", "危急": .critical
        default: .muted
        }
    }
}
