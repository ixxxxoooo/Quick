// CalendarService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import EventKit
import Foundation
import QuickCore

/// 日历服务
///
/// 封装 EventKit 操作，提供日历事件查询。
@MainActor
@Observable
final class CalendarService {

    private let eventStore = EKEventStore()
    private var hasAccess = false

    private let log = QuickLog.plugin("calendar")

    /// 请求日历访问权限
    func requestAccess() {
        Task {
            do {
                hasAccess = try await eventStore.requestFullAccessToEvents()
            } catch {
                log.error("请求日历权限失败: \(error.localizedDescription, privacy: .public)")
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

        return CalendarEvent.sortedByStart(
            events.map { event in
                CalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "无标题",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarColor: ""
                )
            })
    }

    /// 获取农历日期信息
    func lunarDateInfo() -> String {
        CalendarFormatting.lunar(for: Date())
    }
}
