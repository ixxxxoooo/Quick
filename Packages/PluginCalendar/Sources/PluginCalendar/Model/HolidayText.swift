// HolidayText.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 节假日的展示文案
///
/// 放在 Model 层是为了让「还有几天」「放几天」这类措辞能被测试钉住：
/// 视图和主搜索共用同一份，不会各说各话。
extension HolidayPeriod {

    /// 日期范围：同月省略后一半的月份（「2月15日–23日」），跨月写全（「9月30日–10月7日」）
    var rangeText: String {
        guard dayCount > 1 else { return start.monthDayText }
        let tail = start.month == end.month ? "\(end.day)日" : end.monthDayText
        return "\(start.monthDayText)–\(tail)"
    }

    /// 补班日：「补班 9月20日、10月10日」；没有补班返回 `nil`
    var makeupText: String? {
        makeupWorkdays.isEmpty ? nil : "补班 " + makeupWorkdays.map(\.monthDayText).joined(separator: "、")
    }

    /// 相对 `today` 的状态：「放假中 · 第 2 天 / 共 7 天」「明天开始」「还有 17 天」「已结束」
    func countdownText(from today: CivilDate) -> String {
        if let number = dayNumber(of: today) { return "放假中 · 第 \(number) 天 / 共 \(dayCount) 天" }
        let days = today.days(until: start)
        switch days {
        case ..<0: return "已结束"
        case 1: return "明天开始"
        default: return "还有 \(days) 天"
        }
    }

    /// 倒数一句话：「距国庆节还有 17 天」「明天放假：国庆节」「国庆节 · 第 2 天 / 共 7 天」
    func headline(from today: CivilDate) -> String {
        if let number = dayNumber(of: today) { return "\(name) · 第 \(number) 天 / 共 \(dayCount) 天" }
        let days = today.days(until: start)
        return days == 1 ? "明天放假：\(name)" : "距\(name)还有 \(days) 天"
    }

    /// 一行摘要：「国庆节 · 10月1日–7日 · 共 7 天」
    var summaryText: String {
        "\(name) · \(rangeText) · 共 \(dayCount) 天"
    }
}

extension HolidayStatus {

    /// 月历格子的角标：休 / 班
    var badge: String {
        switch self {
        case .off: "休"
        case .makeupWorkday: "班"
        }
    }

    /// 详情里的完整说明
    var detailText: String {
        switch self {
        case .off(let period, let number): "\(period.name) · 放假第 \(number) 天，共 \(period.dayCount) 天"
        case .makeupWorkday(let name): "\(name)调休 · 需上班"
        }
    }
}
