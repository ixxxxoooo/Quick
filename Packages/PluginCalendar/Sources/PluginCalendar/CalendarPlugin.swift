// CalendarPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 日历插件
///
/// 使用 EventKit 读取系统日历事件，显示今日和近期日程；
/// 月历带农历、24 节气、传统节日（精简黄历）与中国法定节假日（含调休补班）。
@MainActor
public final class CalendarPlugin: QuickPlugin, PluginViewProviding, PluginSettingsProviding {

    public static let id = "calendar"
    public static let name = "日历"
    public static let icon = "calendar"
    public static let description = "月历带农历、节气、传统节日与中国法定节假日（休 / 班），同步展示系统日历日程并自动识别会议链接。"
    public static let triggerWords = ["日历", "农历", "节气", "节假日", "假期", "calendar", "lunar", "holiday"]

    public var isEnabled = true

    private let log = QuickLog.plugin(CalendarPlugin.id)

    /// 搜索词分类：节假日 / 节气 / 农历各有自己的结果，其余（日历、calendar）走日程
    private nonisolated static let holidayWords = ["节假日", "假期", "holiday"]
    private nonisolated static let solarTermWords = ["节气"]
    private nonisolated static let lunarWords = ["农历", "lunar"]

    /// 日历服务
    private let calendarService: CalendarService
    /// 节假日数据（Sendable：搜索路径是 `nonisolated`，直接读）
    private let holidayStore: HolidayStore
    /// 当前时间。注入是为了让「还有几天」这类结果能在测试里钉住
    private let now: @Sendable () -> Date

    public init() {
        calendarService = CalendarService()
        holidayStore = HolidayStore()
        now = { Date() }
    }

    /// 测试用：注入固定权限状态的服务、独立缓存的节假日数据与固定时间
    init(
        service: CalendarService,
        holidayStore: HolidayStore = HolidayStore(suiteName: "quick.test.calendar.plugin"),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        calendarService = service
        self.holidayStore = holidayStore
        self.now = now
    }

    // MARK: - QuickPlugin 协议

    public func accepts(query: String) -> Bool {
        query.matchesAnyTrigger(Self.triggerWords)
    }

    public nonisolated func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }

        let today = CivilDate(now())
        if query.matchesAnyTrigger(Self.holidayWords) { return holidayItems(today: today) }
        if query.matchesAnyTrigger(Self.solarTermWords) { return solarTermItems(today: today) }
        if query.matchesAnyTrigger(Self.lunarWords) { return lunarItems(today: today) }

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

    // MARK: - 节假日 / 节气 / 农历结果

    private nonisolated func navigateAction() -> @Sendable @MainActor () -> Void {
        { EventBus.shared.post(NavigateEvent(pluginID: Self.id)) }
    }

    /// 近期节假日：正在放的和接下来的，共 3 段
    private nonisolated func holidayItems(today: CivilDate) -> [SearchableItem] {
        let periods = holidayStore.calendar.upcoming(from: today, limit: 3)
        guard !periods.isEmpty else {
            return [
                SearchableItem(
                    id: "calendar.holiday.none", pluginID: Self.id,
                    title: "暂无已公布的节假日安排", subtitle: "放假安排公布后会自动更新",
                    icon: "party.popper", relevance: 0.5, action: navigateAction())
            ]
        }
        return periods.map { period in
            SearchableItem(
                id: "calendar.holiday.\(period.start.julianDay)", pluginID: Self.id,
                title: "\(period.name) · \(period.countdownText(from: today))",
                subtitle: [period.rangeText + " · 共 \(period.dayCount) 天", period.makeupText]
                    .compactMap { $0 }.joined(separator: " · "),
                icon: "party.popper", relevance: 0.6, action: navigateAction())
        }
    }

    /// 下一个节气（当天交节气就是今天）
    private nonisolated func solarTermItems(today: CivilDate) -> [SearchableItem] {
        guard let next = SolarTerm.next(onOrAfter: today) else { return [] }
        let days = today.days(until: next.date)
        let when = days == 0 ? "今天" : "\(next.date.monthDayText) · 还有 \(days) 天"
        return [
            SearchableItem(
                id: "calendar.solarTerm", pluginID: Self.id,
                title: days == 0 ? "今天是\(next.name)" : "下一个节气：\(next.name)", subtitle: when,
                icon: "leaf", relevance: 0.6, action: navigateAction())
        ]
    }

    /// 今天的农历、干支与节日
    private nonisolated func lunarItems(today: CivilDate) -> [SearchableItem] {
        let day = Almanac.day(for: today)
        let subtitle = ([day.ganzhiText + " · 属" + day.zodiac] + day.highlights).joined(separator: " · ")
        return [
            SearchableItem(
                id: "calendar.lunar", pluginID: Self.id,
                title: "今天 · 农历\(day.lunarText)", subtitle: subtitle,
                icon: "moon.stars", relevance: 0.6, action: navigateAction())
        ]
    }

    public func makeView() -> AnyView {
        AnyView(CalendarView(service: calendarService, holidayStore: holidayStore))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(CalendarSettingsView(holidayStore: holidayStore))
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
