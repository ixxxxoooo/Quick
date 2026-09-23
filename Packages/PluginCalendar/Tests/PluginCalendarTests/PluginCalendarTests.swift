// PluginCalendarTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginCalendar

/// 时间一律按显式公历构造：系统日历设置（例如佛历）不该影响测试结果
private func gregorianDate(
    year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return calendar.date(from: components)!
}

private func makeEvent(
    id: String = "e",
    title: String = "事件",
    start: Date,
    end: Date,
    isAllDay: Bool = false
) -> CalendarEvent {
    CalendarEvent(
        id: id,
        title: title,
        startDate: start,
        endDate: end,
        isAllDay: isAllDay,
        calendarColor: ""
    )
}

@Suite("日历事件时间范围")
struct CalendarEventTimeRangeTests {

    @Test("定时事件显示为「起 - 止」，都是 24 小时制两位")
    func timedEvent() {
        let event = makeEvent(
            start: gregorianDate(year: 2026, month: 9, day: 21, hour: 9, minute: 30),
            end: gregorianDate(year: 2026, month: 9, day: 21, hour: 10, minute: 15)
        )
        #expect(event.timeRange == "09:30 - 10:15")
    }

    /// 全天事件没有有意义的起止时刻，显示 "00:00 - 00:00" 只会误导
    @Test("全天事件只显示「全天」，与起止时刻无关")
    func allDayEvent() {
        let event = makeEvent(
            start: gregorianDate(year: 2026, month: 9, day: 21, hour: 0),
            end: gregorianDate(year: 2026, month: 9, day: 21, hour: 23, minute: 59),
            isAllDay: true
        )
        #expect(event.timeRange == "全天")
    }

    /// 跨零点事件只显示时刻，不显示日期 —— 这里记录当前行为：
    /// 23:00 - 01:30 看不出跨天，属于已知的展示限制
    @Test("跨零点事件按各自时刻显示")
    func overnightEvent() {
        let event = makeEvent(
            start: gregorianDate(year: 2026, month: 9, day: 21, hour: 23),
            end: gregorianDate(year: 2026, month: 9, day: 22, hour: 1, minute: 30)
        )
        #expect(event.timeRange == "23:00 - 01:30")
    }

    @Test("整点补零，个位小时也是两位")
    func padsSingleDigitHour() {
        let event = makeEvent(
            start: gregorianDate(year: 2026, month: 9, day: 21, hour: 8),
            end: gregorianDate(year: 2026, month: 9, day: 21, hour: 9, minute: 5)
        )
        #expect(event.timeRange == "08:00 - 09:05")
    }
}

@Suite("日历事件排序")
struct CalendarEventSortingTests {

    @Test("按开始时间升序")
    func sortsAscending() {
        let nine = makeEvent(
            id: "c", start: gregorianDate(year: 2026, month: 9, day: 21, hour: 9),
            end: gregorianDate(year: 2026, month: 9, day: 21, hour: 10))
        let noon = makeEvent(
            id: "a", start: gregorianDate(year: 2026, month: 9, day: 21, hour: 12),
            end: gregorianDate(year: 2026, month: 9, day: 21, hour: 13))
        let two = makeEvent(
            id: "b", start: gregorianDate(year: 2026, month: 9, day: 21, hour: 14),
            end: gregorianDate(year: 2026, month: 9, day: 21, hour: 15))

        let sorted = CalendarEvent.sortedByStart([two, nine, noon])
        #expect(sorted.map(\.id) == ["c", "a", "b"])
    }

    @Test("已有序的输入保持原顺序")
    func keepsOrderedInput() {
        let first = makeEvent(
            id: "1", start: gregorianDate(year: 2026, month: 9, day: 21, hour: 8),
            end: gregorianDate(year: 2026, month: 9, day: 21, hour: 9))
        let second = makeEvent(
            id: "2", start: gregorianDate(year: 2026, month: 9, day: 21, hour: 10),
            end: gregorianDate(year: 2026, month: 9, day: 21, hour: 11))

        #expect(CalendarEvent.sortedByStart([first, second]).map(\.id) == ["1", "2"])
    }

    @Test("空输入返回空")
    func emptyStaysEmpty() {
        #expect(CalendarEvent.sortedByStart([]).isEmpty)
    }
}

@Suite("农历文本")
struct CalendarFormattingTests {

    /// 农历文本由「中国日历 + zh_CN」这组配置决定，配置被改会在界面上悄悄变化，
    /// 所以用固定公历日期把输出钉住
    @Test("固定日期的农历文本")
    func lunarText() {
        #expect(CalendarFormatting.lunar(for: gregorianDate(year: 2026, month: 9, day: 21)) == "2026丙午年八月十一")
        #expect(CalendarFormatting.lunar(for: gregorianDate(year: 2026, month: 2, day: 17)) == "2026丙午年正月初一")
        #expect(CalendarFormatting.lunar(for: gregorianDate(year: 2024, month: 2, day: 10)) == "2024甲辰年正月初一")
        #expect(CalendarFormatting.lunar(for: gregorianDate(year: 2000, month: 1, day: 1)) == "1999己卯年冬月廿五")
    }

    /// 农历新年当天必须落在「正月初一」，这是最容易看出来的整体错位
    @Test("春节当天是正月初一")
    func springFestival() {
        #expect(CalendarFormatting.lunar(for: gregorianDate(year: 2026, month: 2, day: 17)).hasSuffix("正月初一"))
    }
}

@MainActor
@Suite("日历服务无权限路径")
struct CalendarServiceTests {

    /// 没申请过权限时必须直接返回空，绝不隐式读取或触发系统弹窗
    @Test("未获授权时不读取任何事件")
    func noAccessReturnsEmpty() async {
        let service = CalendarService()
        #expect(await service.todayEvents().isEmpty)
    }

    @Test("农历信息非空")
    func lunarInfoNonEmpty() {
        #expect(!CalendarService().lunarDateInfo().isEmpty)
    }
}

@MainActor
@Suite("日历插件契约")
struct CalendarPluginTests {

    @Test("元数据符合插件约定")
    func metadata() {
        #expect(CalendarPlugin.id == "calendar")
        #expect(CalendarPlugin.id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
        #expect(CalendarPlugin.name == "日历")
        #expect(CalendarPlugin.icon == "calendar")
        #expect(
            CalendarPlugin.triggerWords == ["日历", "农历", "节气", "节假日", "假期", "calendar", "lunar", "holiday"])
    }

    /// 测试进程里没有日历权限，所以 `todayEvents()` 走空分支 —— 插件应给出
    /// 一条「今日无日程」而不是没有任何结果
    @Test("命中触发词时至少返回一条今日入口")
    func triggerReturnsTodayEntry() async {
        let plugin = CalendarPlugin()
        let items = await plugin.searchItems(query: "日历")

        #expect(items.count == 1)
        #expect(items.first?.id == "calendar.today")
        #expect(items.first?.pluginID == CalendarPlugin.id)
        #expect(items.first?.title == "今日无日程")
        #expect(items.first?.relevance == 0.5)
    }

    /// 拉丁触发词按整词匹配，所以 `calendars` 不会误开日历。
    /// 中文触发词按包含匹配，`我的日历`、`查看节假日` 仍然进得来。
    @Test("触发词按整词或中文包含匹配")
    func triggerGateUsesSharedMatcher() async {
        let plugin = CalendarPlugin()

        #expect(!(await plugin.searchItems(query: "calendar")).isEmpty)
        #expect(!(await plugin.searchItems(query: "我的日历")).isEmpty)
        #expect(!(await plugin.searchItems(query: "节假日")).isEmpty)
        #expect(await plugin.searchItems(query: "calendars").isEmpty)
    }

    @Test("未命中触发词时不返回任何结果")
    func unrelatedQueryReturnsNothing() async {
        let plugin = CalendarPlugin()
        #expect(await plugin.searchItems(query: "天气").isEmpty)
        #expect(await plugin.searchItems(query: "clipboard").isEmpty)
        #expect(await plugin.searchItems(query: "").isEmpty)
    }

    /// 无权限时走「今日无日程」占位项，回车仍应跳进日历面板
    @Test("今日占位项执行 action 会发布 NavigateEvent")
    func todayPlaceholderNavigatesToPlugin() async throws {
        let plugin = CalendarPlugin()
        let item = try #require(await plugin.searchItems(query: "日历").first)

        var navigated: [NavigateEvent] = []
        let subscription = EventBus.shared.on(NavigateEvent.self) { navigated.append($0) }
        defer { subscription.cancel() }

        item.action()
        #expect(navigated.count == 1)
        #expect(navigated.first?.pluginID == CalendarPlugin.id)
        #expect(navigated.first?.context.isEmpty == true)
    }
}
