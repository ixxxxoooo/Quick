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
        isAllDay: isAllDay
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

@MainActor
@Suite("日历服务无权限路径")
struct CalendarServiceTests {

    /// 没申请过权限时必须直接返回空，绝不隐式读取或触发系统弹窗
    @Test("未获授权时不读取任何事件")
    func noAccessReturnsEmpty() async {
        let service = CalendarService(accessState: .notDetermined)
        #expect(await service.todayEvents().isEmpty)
        #expect(CalendarService(accessState: .denied).events(on: Date()).isEmpty)
        #expect(CalendarService(accessState: .denied).daysWithEvents(inMonthOf: Date()).isEmpty)
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

    /// 已授权但今天没有日程：给一条「今日无日程」而不是没有任何结果
    @Test("已授权且无日程时返回今日占位项")
    func triggerReturnsTodayEntry() async {
        let plugin = CalendarPlugin(service: CalendarService(accessState: .authorized))
        let items = await plugin.dynamicSearch(query: "日历")

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
        let plugin = CalendarPlugin(service: CalendarService(accessState: .authorized))

        #expect(!(await plugin.dynamicSearch(query: "calendar")).isEmpty)
        #expect(!(await plugin.dynamicSearch(query: "我的日历")).isEmpty)
        #expect(!(await plugin.dynamicSearch(query: "节假日")).isEmpty)
        #expect(await plugin.dynamicSearch(query: "calendars").isEmpty)
    }

    @Test("未命中触发词时不返回任何结果")
    func unrelatedQueryReturnsNothing() async {
        let plugin = CalendarPlugin(service: CalendarService(accessState: .authorized))
        #expect(await plugin.dynamicSearch(query: "天气").isEmpty)
        #expect(await plugin.dynamicSearch(query: "clipboard").isEmpty)
        #expect(await plugin.dynamicSearch(query: "").isEmpty)
    }

    /// 无日程时走「今日无日程」占位项，回车仍应跳进日历面板
    @Test("今日占位项执行 action 会发布 NavigateEvent")
    func todayPlaceholderNavigatesToPlugin() async throws {
        let plugin = CalendarPlugin(service: CalendarService(accessState: .authorized))
        let item = try #require(await plugin.dynamicSearch(query: "日历").first)

        var navigated: [NavigateEvent] = []
        let subscription = EventBus.shared.on(NavigateEvent.self) { navigated.append($0) }
        defer { subscription.cancel() }

        item.action()
        #expect(navigated.count == 1)
        #expect(navigated.first?.pluginID == CalendarPlugin.id)
        #expect(navigated.first?.context.isEmpty == true)
    }

    /// 未授权时说「今日无日程」会让人误以为真的没事 —— 必须给授权入口
    @Test("未授权时给出授权入口，而不是「今日无日程」", arguments: [
        CalendarService.AccessState.notDetermined, .denied,
    ])
    func unauthorizedShowsPermissionEntry(state: CalendarService.AccessState) async throws {
        let plugin = CalendarPlugin(service: CalendarService(accessState: state))
        let items = await plugin.dynamicSearch(query: "日历")
        #expect(items.count == 1)
        #expect(items.first?.id == "calendar.permission")
        #expect(items.first?.title == "需要日历访问权限")
    }
}

@Suite("会议链接识别")
struct MeetingLinkExtractorTests {

    @Test("识别主流会议服务", arguments: [
        "https://zoom.us/j/123456789?pwd=abc",
        "https://us02web.zoom.us/j/123",
        "https://meeting.tencent.com/dm/abcdef",
        "https://meet.google.com/abc-defg-hij",
        "https://teams.microsoft.com/l/meetup-join/xyz",
        "https://vc.feishu.cn/j/123456",
        "https://voovmeeting.com/dm/xxx",
    ])
    func recognisesKnownServices(link: String) {
        let found = MeetingLinkExtractor.firstLink(in: ["会议链接：\(link) 请准时参加"])
        #expect(found?.absoluteString == link)
    }

    @Test("普通链接不算会议，伪造的相似域名也不算")
    func ignoresOrdinaryLinks() {
        #expect(MeetingLinkExtractor.firstLink(in: ["文档 https://example.com/doc"]) == nil)
        #expect(MeetingLinkExtractor.firstLink(in: ["https://notzoom.us.evil.com/j/1"]) == nil)
        #expect(MeetingLinkExtractor.firstLink(in: ["https://evilzoom.us/j/1"]) == nil)
    }

    @Test("按传入顺序取第一个，nil 与空串被跳过")
    func honoursPriorityOrder() {
        let found = MeetingLinkExtractor.firstLink(in: [
            nil, "", "https://meet.google.com/aaa-bbbb-ccc", "https://zoom.us/j/1",
        ])
        #expect(found?.host() == "meet.google.com")
        #expect(MeetingLinkExtractor.firstLink(in: []) == nil)
    }
}

@Suite("开始前提醒计划")
struct ReminderPlannerTests {

    private let now = gregorianDate(year: 2026, month: 10, day: 13, hour: 9)

    private func event(_ id: String, hour: Int, minute: Int = 0, allDay: Bool = false) -> CalendarEvent {
        makeEvent(
            id: id,
            start: gregorianDate(year: 2026, month: 10, day: 13, hour: hour, minute: minute),
            end: gregorianDate(year: 2026, month: 10, day: 13, hour: hour + 1, minute: minute),
            isAllDay: allDay)
    }

    @Test("按提前量算出提醒时刻")
    func firesBeforeStart() throws {
        let plan = ReminderPlanner.plan(events: [event("a", hour: 10)], now: now, leadMinutes: 15)
        let reminder = try #require(plan.first)
        #expect(reminder.fireDate == gregorianDate(year: 2026, month: 10, day: 13, hour: 9, minute: 45))
    }

    @Test("关闭（0）时不提醒")
    func zeroDisablesReminders() {
        #expect(ReminderPlanner.plan(events: [event("a", hour: 10)], now: now, leadMinutes: 0).isEmpty)
    }

    @Test("全天事件、已开始事件、提醒时刻已过的事件都不提醒")
    func skipsNonRemindable() {
        let plan = ReminderPlanner.plan(
            events: [
                event("allday", hour: 0, allDay: true),
                event("started", hour: 8),
                event("tooLate", hour: 9, minute: 5),
                event("ok", hour: 11),
            ],
            now: now, leadMinutes: 10)
        #expect(plan.map(\.eventID) == ["ok"])
    }

    @Test("同一事件 id 只提醒一次，且按时间排序")
    func dedupesAndSorts() {
        let plan = ReminderPlanner.plan(
            events: [event("b", hour: 12), event("a", hour: 10), event("a", hour: 11)],
            now: now, leadMinutes: 5)
        #expect(plan.map(\.eventID) == ["a", "b"])
        #expect(plan.first?.event.startDate == gregorianDate(year: 2026, month: 10, day: 13, hour: 10))
    }
}

@Suite("月历网格与周数")
struct CalendarGridTests {

    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    @Test("2026 年 10 月（周日起）：首日是周四，补 4 个空格，共 5 行")
    func octoberSundayStart() {
        let cal = calendar(firstWeekday: 1)
        let rows = CalendarFormatting.monthGrid(containing: gregorianDate(year: 2026, month: 10, day: 13), calendar: cal)
        #expect(rows.count == 5)
        #expect(rows.allSatisfy { $0.cells.count == 7 })
        #expect(rows[0].cells.prefix(4).allSatisfy { $0.date == nil })
        let first = rows[0].cells[4].date
        #expect(first.map { cal.component(.day, from: $0) } == 1)
        #expect(rows.flatMap(\.cells).compactMap(\.date).count == 31)
    }

    @Test("周一起排时补位随之改变")
    func mondayStart() {
        let cal = calendar(firstWeekday: 2)
        let rows = CalendarFormatting.monthGrid(containing: gregorianDate(year: 2026, month: 10, day: 13), calendar: cal)
        #expect(rows[0].cells.prefix(3).allSatisfy { $0.date == nil })
        #expect(rows[0].cells[3].date != nil)
        #expect(CalendarFormatting.weekdaySymbols(calendar: cal).count == 7)
    }

    @Test("恰好排满 4 行的二月（2026 年 2 月，周日起）")
    func februaryFitsFourRows() {
        let rows = CalendarFormatting.monthGrid(
            containing: gregorianDate(year: 2026, month: 2, day: 10), calendar: calendar(firstWeekday: 1))
        #expect(rows.count == 4)
        #expect(rows.flatMap(\.cells).compactMap(\.date).count == 28)
    }

    @Test("周数跟随日历规则：2026-01-01 落在第 1 周，2026-12-31 落在第 53 周（ISO 规则）")
    func weekNumbers() {
        let cal = calendar(firstWeekday: 2)
        #expect(CalendarFormatting.weekNumber(for: gregorianDate(year: 2026, month: 1, day: 1), calendar: cal) == 1)
        #expect(CalendarFormatting.weekNumber(for: gregorianDate(year: 2026, month: 12, day: 31), calendar: cal) == 53)
    }
}

@Suite("日历偏好")
struct CalendarPreferencesTests {

    @Test("缺省值与设置页一致，非法值被夹住")
    func defaultsAndClamping() {
        let suite = UserDefaults(suiteName: "calendar.prefs.\(UUID().uuidString)")!
        #expect(CalendarPreferences.reminderMinutes(defaults: suite) == 10)
        #expect(CalendarPreferences.extractsMeetingLinks(defaults: suite))
        #expect(!CalendarPreferences.showsWeekNumber(defaults: suite))
        #expect(CalendarPreferences.showsHolidays(defaults: suite))
        #expect(CalendarPreferences.showsAlmanac(defaults: suite))
        #expect(CalendarPreferences.updatesHolidaysOnline(defaults: suite))

        suite.set(false, forKey: PluginSettingKey.Calendar.showHolidays)
        suite.set(false, forKey: PluginSettingKey.Calendar.showAlmanac)
        suite.set(false, forKey: PluginSettingKey.Calendar.updateHolidaysOnline)
        #expect(!CalendarPreferences.showsHolidays(defaults: suite))
        #expect(!CalendarPreferences.showsAlmanac(defaults: suite))
        #expect(!CalendarPreferences.updatesHolidaysOnline(defaults: suite))

        suite.set(-5, forKey: PluginSettingKey.Calendar.reminderMinutes)
        #expect(CalendarPreferences.reminderMinutes(defaults: suite) == 0)
        suite.set(0, forKey: PluginSettingKey.Calendar.reminderMinutes)
        #expect(CalendarPreferences.reminderMinutes(defaults: suite) == 0, "0 是合法值：不提醒")
        suite.set(false, forKey: PluginSettingKey.Calendar.autoExtractMeetingLinks)
        #expect(!CalendarPreferences.extractsMeetingLinks(defaults: suite))
    }
}
