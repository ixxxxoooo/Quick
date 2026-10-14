// CalendarDayLayout.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 周视图与日视图的事件布局（纯逻辑）
enum CalendarDayLayout {

    /// 一天的分钟数
    static let minutesPerDay = 24 * 60

    /// 时间轴上事件块的最短时长：过短的事件（提醒类）也要有可点的高度
    static let minimumDurationMinutes = 30

    /// 按天归并事件：跨天事件在它覆盖的每一天都出现
    ///
    /// 返回的键是每个 `day` 的零点；没有事件的日子也有一个空数组，调用方不用判空。
    static func eventsByDay(
        _ events: [CalendarEvent], days: [Date], calendar: Calendar = .current
    ) -> [Date: [CalendarEvent]] {
        var result: [Date: [CalendarEvent]] = [:]
        for day in days {
            let start = calendar.startOfDay(for: day)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            result[start] = events.filter { overlaps($0, start: start, end: end) }
        }
        return result
    }

    /// 时间轴上的一块
    struct PlacedEvent: Identifiable, Equatable {
        let event: CalendarEvent
        /// 当天内的起止分钟（已裁到 0…1440，且不短于最短时长）
        let startMinute: Int
        let endMinute: Int
        /// 重叠时的并排列号与该组的总列数
        let column: Int
        let columnCount: Int

        var id: String { event.id + "@\(startMinute)" }
    }

    /// 日视图时间轴的布局结果
    struct Timeline: Equatable {
        /// 全天事件，置顶展示
        let allDay: [CalendarEvent]
        let placed: [PlacedEvent]
    }

    /// 某一天的时间轴：全天事件单列，其余按时间摆放，重叠的并排分列
    static func timeline(
        events: [CalendarEvent], on day: Date, calendar: Calendar = .current
    ) -> Timeline {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return Timeline(allDay: [], placed: [])
        }
        let todays = events.filter { overlaps($0, start: start, end: end) }
        let allDay = todays.filter(\.isAllDay)

        struct Span {
            let event: CalendarEvent
            let start: Int
            let end: Int
        }
        let spans: [Span] = todays.filter { !$0.isAllDay }.map { event in
            let from = max(0, minutes(from: start, to: event.startDate))
            let to = min(minutesPerDay, minutes(from: start, to: event.endDate))
            return Span(event: event, start: from, end: max(to, min(from + minimumDurationMinutes, minutesPerDay)))
        }.sorted { ($0.start, $0.end) < ($1.start, $1.end) }

        // 把「首尾相连地重叠」的事件分进同一簇，簇内贪心分列
        var placed: [PlacedEvent] = []
        var cluster: [(span: Span, column: Int)] = []
        var columnEnds: [Int] = []
        var clusterEnd = 0

        func flush() {
            let count = max(columnEnds.count, 1)
            placed += cluster.map {
                PlacedEvent(
                    event: $0.span.event, startMinute: $0.span.start, endMinute: $0.span.end,
                    column: $0.column, columnCount: count)
            }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for span in spans {
            if !cluster.isEmpty && span.start >= clusterEnd { flush() }
            let column = columnEnds.firstIndex { $0 <= span.start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(span.end) } else { columnEnds[column] = span.end }
            // 先更新簇的右边界再入簇：新簇的第一个事件要重置边界，而不是沿用上一簇的
            clusterEnd = cluster.isEmpty ? span.end : max(clusterEnd, span.end)
            cluster.append((span, column))
        }
        flush()

        return Timeline(allDay: allDay, placed: placed)
    }

    /// 日视图首次显示时时间轴该滚到哪个整点
    ///
    /// 有事件就对准第一件事前一小时；没有事件、是今天就对准「现在」前两小时；
    /// 其余日子落在上午 8 点 —— 总之别把用户晾在凌晨 0 点的空白里。
    static func initialScrollHour(timeline: Timeline, isToday: Bool, nowMinute: Int) -> Int {
        let hour: Int
        if let first = timeline.placed.map(\.startMinute).min() {
            hour = first / 60 - 1
        } else if isToday {
            hour = nowMinute / 60 - 2
        } else {
            hour = defaultScrollHour
        }
        return min(max(hour, 0), 24 - 1)
    }

    /// 没有任何线索时的起始整点
    static let defaultScrollHour = 8

    // MARK: - 内部

    /// 事件是否与 [start, end) 有交集；零时长事件按开始时刻算
    private static func overlaps(_ event: CalendarEvent, start: Date, end: Date) -> Bool {
        if event.endDate <= event.startDate {
            return event.startDate >= start && event.startDate < end
        }
        return event.startDate < end && event.endDate > start
    }

    private static func minutes(from base: Date, to date: Date) -> Int {
        Int((date.timeIntervalSince(base) / 60).rounded())
    }
}
