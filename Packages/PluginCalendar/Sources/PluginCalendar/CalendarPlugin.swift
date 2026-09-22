// CalendarPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import EventKit
import QuickCore
import QuickUI
import SwiftUI

/// 日历插件
///
/// 使用 EventKit 读取系统日历事件，显示今日和近期日程。
/// 支持农历显示。
@MainActor
public final class CalendarPlugin: QuickPlugin {

    public static let id = "calendar"
    public static let name = "日历"
    public static let icon = "calendar"
    public static let description = "同步展示系统日历日程与近期事件安排，支持会议链接自动识别与农历视图显示。"
    public static let triggerWords = ["日历", "农历", "节气", "节假日", "假期", "calendar", "lunar", "holiday"]

    public var isEnabled = true

    private let log = QuickLog.plugin(CalendarPlugin.id)

    /// EventKit 事件存储
    private let eventStore = EKEventStore()

    /// 日历服务
    private let calendarService: CalendarService

    public init() {
        calendarService = CalendarService()
    }

    // MARK: - QuickPlugin 协议

    public func accepts(query: String) -> Bool {
        query.matchesAnyTrigger(Self.triggerWords)
    }

    public func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }
        return await searchItems(query: query)
    }

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }

        let todayEvents = await calendarService.todayEvents()
        if todayEvents.isEmpty {
            return [
                SearchableItem(
                    id: "calendar.today",
                    pluginID: Self.id,
                    title: "今日无日程",
                    subtitle: Date().formatted(date: .complete, time: .omitted),
                    icon: "calendar",
                    relevance: 0.5,
                    action: {}
                )
            ]
        }

        return todayEvents.prefix(5).map { event in
            SearchableItem(
                id: "calendar.\(event.id)",
                pluginID: Self.id,
                title: event.title,
                subtitle: event.timeRange,
                icon: "calendar",
                relevance: 0.6,
                action: {}
            )
        }
    }

    public func makeView() -> AnyView {
        AnyView(CalendarView(service: calendarService))
    }

    public func activate() {
        calendarService.requestAccess()
        log.notice("插件已激活，已发起日历权限申请")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
