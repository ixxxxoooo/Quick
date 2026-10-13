// PingModels.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 网络工具的偏好读取
///
/// 每次用的时候现读（设置页可以在运行期改），并夹到合理范围：
/// `UserDefaults` 里的值可能被手工改坏，不能把 0 次或 9999 秒传给 `ping`。
public enum NetworkToolsPreferences {

    public static let defaultPingCount = 4
    public static let defaultTimeout = 5

    /// Ping 发送的包数
    public static func pingCount(defaults: UserDefaults = .standard) -> Int {
        clamp(defaults.object(forKey: PluginSettingKey.NetworkTools.pingCount) as? Int ?? defaultPingCount, 1...20)
    }

    /// 超时秒数（每个包等回应的上限，同时也是网络请求的上限）
    public static func timeout(defaults: UserDefaults = .standard) -> Int {
        clamp(defaults.object(forKey: PluginSettingKey.NetworkTools.timeout) as? Int ?? defaultTimeout, 1...30)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Ping 目标的校验
///
/// 目标会作为参数交给 `/sbin/ping`。不走 shell，所以没有命令注入，但以 `-` 开头的串
/// 会被当成选项（例如 `-f` 洪泛），因此只放行主机名与 IP 字面量里可能出现的字符。
public enum PingTarget {

    /// 规整并校验；不合法返回 `nil`
    public static func validated(_ raw: String) -> String? {
        let host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host.count <= 253, !host.hasPrefix("-") else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:_")
        guard host.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return host
    }
}

/// 一次 Ping 的汇总
public struct PingSummary: Equatable, Sendable {
    public let transmitted: Int
    public let received: Int
    /// 丢包率，0–100
    public let lossPercent: Double
    public let minMs: Double?
    public let avgMs: Double?
    public let maxMs: Double?

    public init(
        transmitted: Int, received: Int, lossPercent: Double,
        minMs: Double? = nil, avgMs: Double? = nil, maxMs: Double? = nil
    ) {
        self.transmitted = transmitted
        self.received = received
        self.lossPercent = lossPercent
        self.minMs = minMs
        self.avgMs = avgMs
        self.maxMs = maxMs
    }

    /// 一句话结论，给结果卡片用
    public var headline: String {
        if received == 0 { return "不可达（\(transmitted) 个包全部丢失）" }
        let avg = avgMs.map { String(format: "平均 %.1f ms", $0) } ?? "无延迟数据"
        let loss = String(format: "丢包 %.0f%%", lossPercent)
        return "\(avg) · \(loss)"
    }
}

/// `ping` 输出的解析（纯逻辑）
///
/// 只认汇总两行：
/// `N packets transmitted, M packets received, X% packet loss`
/// `round-trip min/avg/max/stddev = a/b/c/d ms`
/// 逐包行不解析 —— 它们只用来原样展示。
public enum PingParser {

    public static func parse(_ output: String) -> PingSummary? {
        var transmitted: Int?
        var received: Int?
        var loss: Double?
        var minMs: Double?
        var avgMs: Double?
        var maxMs: Double?

        for line in output.components(separatedBy: .newlines) {
            if line.contains("packets transmitted") {
                // "4 packets transmitted, 4 packets received, 0.0% packet loss"
                let parts = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                transmitted = parts.first.flatMap(leadingInt)
                received = parts.dropFirst().first(where: { $0.contains("received") }).flatMap(leadingInt)
                loss = parts.first(where: { $0.contains("packet loss") }).flatMap(leadingDouble)
            } else if line.contains("round-trip") || line.hasPrefix("rtt") {
                // "round-trip min/avg/max/stddev = 0.057/0.057/0.057/nan ms"
                guard let equals = line.firstIndex(of: "=") else { continue }
                let numbers = line[line.index(after: equals)...]
                    .replacingOccurrences(of: "ms", with: "")
                    .split(separator: "/")
                    .map { Double($0.trimmingCharacters(in: .whitespaces)) }
                if numbers.count >= 3 {
                    minMs = numbers[0]
                    avgMs = numbers[1]
                    maxMs = numbers[2]
                }
            }
        }
        guard let transmitted, let received else { return nil }
        let computedLoss = loss ?? (transmitted > 0 ? Double(transmitted - received) / Double(transmitted) * 100 : 100)
        return PingSummary(
            transmitted: transmitted, received: received, lossPercent: computedLoss,
            minMs: minMs, avgMs: avgMs, maxMs: maxMs)
    }

    private static func leadingInt(_ text: String) -> Int? {
        Int(text.prefix { $0.isNumber })
    }

    private static func leadingDouble(_ text: String) -> Double? {
        Double(text.prefix { $0.isNumber || $0 == "." })
    }
}
