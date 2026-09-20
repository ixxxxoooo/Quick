// CalendarEvent.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 日历事件
///
/// 纯值类型。EventKit 的 `EKEvent` 只在 `CalendarService` 里被翻译成它一次，
/// 之后插件和视图都只认这个类型 —— 这样「时间范围怎么显示」「事件怎么排序」
/// 这类纯逻辑才能不启动 EventKit 就被测试。
struct CalendarEvent: Identifiable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: String

    /// 时间范围文本
    ///
    /// 全天事件没有有意义的起止时刻，显示 "00:00 - 00:00" 只会误导，
    /// 所以单独走 "全天"。
    var timeRange: String {
        if isAllDay { return "全天" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }

    /// 按开始时间升序
    ///
    /// 抽成函数是为了让「同一天内事件的排列顺序」这条规则能被测试钉住：
    /// 排序错了用户看到的是顺序错乱的日程，而不是一个报错。
    static func sortedByStart(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.sorted { $0.startDate < $1.startDate }
    }
}
