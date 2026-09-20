// TimestampConverterLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 时间戳与日期互转的纯逻辑
///
/// 时区必须由调用方注入。模型层不许读 `TimeZone.current` —— 环境事实一律参数化，
/// 同一个输入在任何机器、任何时区都要得到同一个结果，测试才有东西可断言。
public enum TimestampConverterLogic {

    /// 输入被识别成了什么
    public enum InputType: String, Sendable {
        case empty
        case timestamp
        case date
    }

    /// 结果卡片的一行
    public struct Row: Equatable, Sendable {
        public let key: String
        public let label: String
        public let value: String
    }

    /// 一次转换的完整结果
    public struct Conversion: Equatable, Sendable {
        public let inputType: InputType
        public let rows: [Row]
    }

    /// 「本地时间」的显示格式
    private static let displayFormat = "yyyy-MM-dd HH:mm:ss"

    /// 毫秒时间戳的判定阈值
    ///
    /// 秒级时间戳要到公元 33658 年才会超过 1e12，拿它当分界是安全的；
    /// 边界本身按秒处理，与原工具一致。比较取绝对值 —— 1970 年之前的毫秒时间戳
    /// 是负数，只看 `> 1e12` 会把它们当成秒，差了一千倍。
    private static let millisecondsThreshold: Double = 1e12

    /// 能接受的时间戳上限
    ///
    /// 再大就不是时间戳而是打字打错了，而「大得离谱」和「非有限」一样会溢出
    /// `Int` 转换。1e15 秒 ≈ 公元 3100 万年，远超任何真实用途。
    private static let maximumMagnitude: Double = 1e15

    /// 依次尝试的日期格式
    private static let dateFormats = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "yyyy/MM/dd HH:mm:ss",
        "yyyy/MM/dd", "MM/dd/yyyy"
    ]

    /// 转换输入文本
    ///
    /// - Parameters:
    ///   - text: 用户输入
    ///   - timeZone: 本地时间的显示时区，同时也是无时区日期的解析时区
    /// - Returns: 识别出的输入类型与结果行；无法识别时 `rows` 为空
    public static func convert(_ text: String, timeZone: TimeZone) -> Conversion {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Conversion(inputType: .empty, rows: [])
        }

        // 先试时间戳：纯数字输入几乎不可能是日期
        //
        // 必须挡住非有限值：`Double("inf")` 和 `Double("nan")` 都能解析成功，
        // 而 `Int(inf)` 会直接把进程打崩 —— 一个纯文本输入框不该有让 App 挂掉的能力。
        if let seconds = Double(trimmed), seconds.isFinite, abs(seconds) < maximumMagnitude {
            return Conversion(
                inputType: .timestamp,
                rows: rows(forTimestamp: seconds, timeZone: timeZone)
            )
        }

        // 再试日期：逐个格式试到第一个能解析的为止，顺序与原工具一致
        for format in dateFormats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.timeZone = timeZone
            if let date = formatter.date(from: trimmed) {
                return Conversion(
                    inputType: .date,
                    rows: rows(forDate: date, timeZone: timeZone)
                )
            }
        }

        return Conversion(inputType: .empty, rows: [])
    }

    /// 当前时刻的秒级时间戳文本（「填入当前」按钮用）
    ///
    /// `now` 由调用方注入 —— 模型层直接读系统时钟就没法测了。
    public static func currentTimestamp(now: Date) -> String {
        "\(Int(now.timeIntervalSince1970))"
    }

    // MARK: - 结果行的构造

    /// 时间戳 → 四条结果，秒/毫秒在前因为输入本来就是数字
    private static func rows(forTimestamp value: Double, timeZone: TimeZone) -> [Row] {
        let interval: TimeInterval = abs(value) > millisecondsThreshold ? value / 1000 : value
        let date = Date(timeIntervalSince1970: interval)
        return [
            Row(key: "local", label: "本地时间", value: localString(from: date, timeZone: timeZone)),
            Row(key: "iso", label: "ISO 8601", value: ISO8601DateFormatter().string(from: date)),
            Row(key: "unix", label: "Unix 时间戳（秒）", value: "\(Int(date.timeIntervalSince1970))"),
            Row(
                key: "unixms", label: "Unix 时间戳（毫秒）",
                value: "\(Int(date.timeIntervalSince1970 * 1000))"
            )
        ]
    }

    /// 日期 → 四条结果，顺序与原工具一致
    private static func rows(forDate date: Date, timeZone: TimeZone) -> [Row] {
        [
            Row(key: "unix", label: "Unix 时间戳（秒）", value: "\(Int(date.timeIntervalSince1970))"),
            Row(
                key: "unixms", label: "Unix 时间戳（毫秒）",
                value: "\(Int(date.timeIntervalSince1970 * 1000))"
            ),
            Row(key: "local", label: "本地时间", value: localString(from: date, timeZone: timeZone)),
            Row(key: "iso", label: "ISO 8601", value: ISO8601DateFormatter().string(from: date))
        ]
    }

    /// 按指定时区格式化「本地时间」
    private static func localString(from date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = displayFormat
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
