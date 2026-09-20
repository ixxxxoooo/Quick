// CalendarService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import EventKit
import Foundation

/// 日历服务
///
/// 封装 EventKit 操作，提供日历事件查询。
@MainActor
final class CalendarService: Observable {

    /// 日历事件
    struct CalendarEvent: Identifiable, Sendable {
        let id: String
        let title: String
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool
        let calendarColor: String

        var timeRange: String {
            if isAllDay { return "全天" }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        }
    }

    private let eventStore = EKEventStore()
    private var hasAccess = false

    /// 请求日历访问权限
    func requestAccess() {
        Task {
            do {
                hasAccess = try await eventStore.requestFullAccessToEvents()
            } catch {
                print("[CalendarService] 请求日历权限失败: \(error)")
            }
        }
    }

    /// 获取今日事件
    func todayEvents() async -> [CalendarEvent] {
        guard hasAccess else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = eventStore.events(matching: predicate)

        return events.map { event in
            CalendarEvent(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "无标题",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                calendarColor: ""
            )
        }.sorted { $0.startDate < $1.startDate }
    }

    /// 获取农历日期信息
    func lunarDateInfo() -> String {
        let chinese = Calendar(identifier: .chinese)
        let formatter = DateFormatter()
        formatter.calendar = chinese
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .long
        return formatter.string(from: Date())
    }
}
