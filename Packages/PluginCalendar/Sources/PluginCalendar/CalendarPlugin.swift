// CalendarPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 日历插件
///
/// 使用 EventKit 读取系统日历事件，显示今日和近期日程。
/// 支持农历显示。
@MainActor
public final class CalendarPlugin: QuickPlugin, PluginViewProviding, PluginSettingsProviding {

    public static let id = "calendar"
    public static let name = "日历"
    public static let icon = "calendar"
    public static let description = "同步展示系统日历日程与近期事件安排，支持会议链接自动识别与农历视图显示。"
    public static let triggerWords = ["日历", "农历", "节气", "节假日", "假期", "calendar", "lunar", "holiday"]

    public var isEnabled = true

    private let log = QuickLog.plugin(CalendarPlugin.id)

    /// 日历服务
    private let calendarService: CalendarService

    public init() {
        calendarService = CalendarService()
    }

    /// 测试用：注入固定权限状态的服务
    init(service: CalendarService) {
        calendarService = service
    }

    // MARK: - QuickPlugin 协议

    public func accepts(query: String) -> Bool {
        query.matchesAnyTrigger(Self.triggerWords)
    }

    public nonisolated func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }

        // 未授权时「今日无日程」会误导：给出能点进去授权的入口
        let state = await calendarService.accessState
        if state != .authorized {
            return [
                SearchableItem(
                    id: "calendar.permission",
                    pluginID: Self.id,
                    title: "需要日历访问权限",
                    subtitle: state == .denied ? "在系统设置里允许 Quick 访问日历" : "打开日历插件完成授权",
                    icon: "calendar.badge.exclamationmark",
                    relevance: 0.5,
                    action: {
                        EventBus.shared.post(NavigateEvent(pluginID: Self.id))
                    }
                )
            ]
        }

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
                    action: {
                        EventBus.shared.post(NavigateEvent(pluginID: Self.id))
                    }
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
                action: {
                    EventBus.shared.post(
                        NavigateEvent(pluginID: Self.id, context: ["eventID": event.id]))
                }
            )
        }
    }

    public func makeView() -> AnyView {
        AnyView(CalendarView(service: calendarService))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(CalendarSettingsView())
    }

    /// 不在启动时弹权限框：已授权的用户直接开始提醒，未授权的由日历视图里的按钮触发申请
    public func activate() {
        calendarService.startReminders()
        log.notice("插件已激活，日历权限：\(String(describing: self.calendarService.accessState), privacy: .public)")
    }

    public func deactivate() {
        calendarService.stopReminders()
        log.notice("插件已停用")
    }
}
