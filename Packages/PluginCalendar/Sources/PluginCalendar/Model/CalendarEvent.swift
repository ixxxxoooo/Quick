// CalendarEvent.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 日历颜色（sRGB 分量，0–1）
///
/// 模型层不能 import AppKit / SwiftUI，所以颜色用纯数值带出来，视图层再转成 `Color`。
struct CalendarColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

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
    /// 所属日历的颜色；取不到时为 `nil`，视图用默认色
    let color: CalendarColor?
    /// 地点（日历里填的文本）
    let location: String?
    /// 从标题 / 地点 / 备注 / URL 里识别出的会议链接
    let meetingLink: URL?

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        color: CalendarColor? = nil,
        location: String? = nil,
        meetingLink: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.color = color
        self.location = location
        self.meetingLink = meetingLink
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

    /// 按开始时间升序；同一时刻时全天事件在前，再按标题稳定排序
    ///
    /// 抽成函数是为了让「同一天内事件的排列顺序」这条规则能被测试钉住：
    /// 排序错了用户看到的是顺序错乱的日程，而不是一个报错。
    static func sortedByStart(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.title < rhs.title
        }
    }
}

/// 会议链接识别（纯逻辑）
///
/// 只认主流会议服务的域名：宁可漏识别，也不把备注里随手贴的普通链接当成「加入会议」按钮。
enum MeetingLinkExtractor {

    /// 域名后缀（含子域）。命中其一才算会议链接
    static let knownHosts = [
        "zoom.us", "zoom.com", "zoomgov.com",
        "meeting.tencent.com", "voovmeeting.com",
        "meet.google.com",
        "teams.microsoft.com", "teams.live.com",
        "vc.feishu.cn", "larksuite.com",
        "meeting.dingtalk.com", "n.dingtalk.com",
        "webex.com",
    ]

    /// 从若干段文本里找第一个会议链接
    ///
    /// - Parameter texts: 按优先级排列（先 URL 字段，再地点，再备注）；`nil` 与空串被忽略
    static func firstLink(in texts: [String?]) -> URL? {
        for text in texts {
            guard let text, !text.isEmpty else { continue }
            for url in links(in: text) where isMeetingHost(url.host()) {
                return url
            }
        }
        return nil
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { match in
            guard let url = match.url, let scheme = url.scheme?.lowercased(),
                scheme == "https" || scheme == "http"
            else { return nil }
            return url
        }
    }

    private static func isMeetingHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return knownHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

/// 开始前提醒的计划（纯逻辑）
enum ReminderPlanner {

    /// 一条待发的提醒
    struct Reminder: Equatable, Sendable {
        let eventID: String
        let title: String
        /// 提醒发出的时刻
        let fireDate: Date
        let leadMinutes: Int
        let event: CalendarEvent

        static func == (lhs: Reminder, rhs: Reminder) -> Bool {
            lhs.eventID == rhs.eventID && lhs.fireDate == rhs.fireDate
        }
    }

    /// 算出还没到点的提醒
    ///
    /// - 全天事件没有开始时刻，不提醒。
    /// - 提醒时刻已过（含「事件已开始」）的不再补发。
    /// - `leadMinutes <= 0` 表示关闭提醒。
    /// - 同一个事件 id 只提醒一次（重复事件的各次出现 id 可能相同，取最早的一次）。
    static func plan(events: [CalendarEvent], now: Date, leadMinutes: Int) -> [Reminder] {
        guard leadMinutes > 0 else { return [] }
        var seen = Set<String>()
        var result: [Reminder] = []
        for event in CalendarEvent.sortedByStart(events) where !event.isAllDay {
            let fire = event.startDate.addingTimeInterval(-TimeInterval(leadMinutes * 60))
            guard fire > now, seen.insert(event.id).inserted else { continue }
            result.append(
                Reminder(
                    eventID: event.id, title: event.title, fireDate: fire,
                    leadMinutes: leadMinutes, event: event))
        }
        return result
    }
}
