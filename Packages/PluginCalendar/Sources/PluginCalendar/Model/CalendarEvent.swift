// CalendarEvent.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 日历事件
///
/// 纯值类型。EventKit 的 `EKEvent` 只在 `CalendarService` 里被翻译成它一次，
/// 之后插件和视图都只认这个类型 —— 这样「时间范围怎么显示」「事件怎么排序」
/// 「会议链接怎么提取」这类纯逻辑才能不启动 EventKit 就被测试。
struct CalendarEvent: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: String
    let calendarTitle: String
    let location: String?
    let notes: String?
    let url: URL?

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarColor: String,
        calendarTitle: String = "",
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarColor = calendarColor
        self.calendarTitle = calendarTitle
        self.location = location
        self.notes = notes
        self.url = url
    }

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
        events.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            if lhs.isAllDay != rhs.isAllDay {
                return lhs.isAllDay && !rhs.isAllDay
            }
            return lhs.endDate < rhs.endDate
        }
    }

    /// 判断事件是否落在指定日期当天（包含跨天事件）
    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return false
        }
        if isAllDay {
            let eventStart = calendar.startOfDay(for: startDate)
            let eventEnd = calendar.startOfDay(for: endDate)
            return dayStart >= eventStart && dayStart <= eventEnd
        }
        return startDate < dayEnd && endDate > dayStart
    }

    /// 自动识别在线会议链接（支持腾讯会议、飞书、Zoom、Google Meet、Teams、钉钉、Webex 等）
    var meetingURL: URL? {
        if let url, Self.isMeetingURL(url) {
            return url
        }
        let candidates = [location, notes].compactMap { $0 }
        for text in candidates {
            if let found = Self.extractMeetingURL(from: text) {
                return found
            }
        }
        return url
    }

    /// 从自由文本中提取第一个在线会议 URL
    static func extractMeetingURL(from text: String) -> URL? {
        let pattern = #"https?://[^\s<>\"'）】\)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        for match in matches {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let raw = String(text[swiftRange]).trimmingCharacters(
                in: CharacterSet(charactersIn: ".,;!?，。；！？"))
            if let url = URL(string: raw), isMeetingURL(url) {
                return url
            }
        }
        return nil
    }

    /// 判断 URL 是否属于常见在线会议平台
    static func isMeetingURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let meetingDomains = [
            "meeting.tencent.com",
            "voovmeeting.com",
            "wemeet.qq.com",
            "zoom.us",
            "zoom.com.cn",
            "feishu.cn",
            "larksuite.com",
            "meet.google.com",
            "teams.microsoft.com",
            "teams.live.com",
            "dingtalk.com",
            "webex.com"
        ]
        return meetingDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
