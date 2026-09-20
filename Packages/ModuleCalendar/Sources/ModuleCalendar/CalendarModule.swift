// CalendarModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import EventKit
import QuickCore
import QuickUI
import SwiftUI

/// 日历模块
///
/// 使用 EventKit 读取系统日历事件，显示今日和近期日程。
/// 支持农历显示。
@MainActor
public final class CalendarModule: QuickModule {

    public static let id = "calendar"
    public static let name = "日历"
    public static let icon = "calendar"

    public var isEnabled = true

    private let log = QuickLog.module(CalendarModule.id)

    /// EventKit 事件存储
    private let eventStore = EKEventStore()

    /// 日历服务
    private let calendarService: CalendarService

    public init() {
        calendarService = CalendarService()
    }

    // MARK: - QuickModule 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        let triggers = ["日历", "日程", "calendar", "今天", "日期"]
        guard triggers.contains(where: { query.lowercased().contains($0) }) else { return [] }

        let todayEvents = await calendarService.todayEvents()
        if todayEvents.isEmpty {
            return [
                SearchableItem(
                    id: "calendar.today",
                    moduleID: Self.id,
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
                moduleID: Self.id,
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
        log.notice("模块已激活，已发起日历权限申请")
    }

    public func deactivate() {
        log.notice("模块已停用")
    }
}
