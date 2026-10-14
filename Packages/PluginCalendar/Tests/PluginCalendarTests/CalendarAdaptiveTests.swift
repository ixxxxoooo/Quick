// CalendarAdaptiveTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics
import Foundation
import QuickCore
import Testing

@testable import PluginCalendar

/// 显式公历 + 固定时区：系统日历设置与时区不该影响测试结果
private func makeCalendar(firstWeekday: Int = 1) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    calendar.firstWeekday = firstWeekday
    return calendar
}

private func date(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, calendar: Calendar = makeCalendar()
) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func event(
    _ id: String, _ start: Date, _ end: Date, allDay: Bool = false
) -> CalendarEvent {
    CalendarEvent(id: id, title: id, startDate: start, endDate: end, isAllDay: allDay)
}

// MARK: - 视图模式与导航

@Suite("日历视图模式与导航")
struct CalendarViewModeTests {

    @Test("存储值非法或缺失时回落月视图")
    func fallsBackToMonth() {
        #expect(CalendarViewMode(storedValue: nil) == .month)
        #expect(CalendarViewMode(storedValue: "bogus") == .month)
        #expect(CalendarViewMode(storedValue: "week") == .week)
        #expect(CalendarViewMode(storedValue: "day") == .day)
    }

    @Test("视图模式从偏好读取，缺失为月")
    func preferenceRoundTrip() throws {
        let suite = try #require(UserDefaults(suiteName: "calendar.mode.\(UUID().uuidString)"))
        #expect(CalendarPreferences.viewMode(defaults: suite) == .month)
        suite.set("day", forKey: PluginSettingKey.Calendar.viewMode)
        #expect(CalendarPreferences.viewMode(defaults: suite) == .day)
        suite.set("???", forKey: PluginSettingKey.Calendar.viewMode)
        #expect(CalendarPreferences.viewMode(defaults: suite) == .month)
    }

    @Test("按月移动：31 号夹到短月最后一天，月份同步")
    func monthStepClampsDay() {
        let calendar = makeCalendar()
        let moved = CalendarNavigation.moved(from: date(2026, 1, 31), mode: .month, by: 1, calendar: calendar)
        #expect(moved.selectedDate == date(2026, 2, 28))
        #expect(moved.displayedMonth == date(2026, 2, 1))
    }

    @Test("按周移动：跨月跨年时月份跟着走")
    func weekStepCrossesBoundaries() {
        let calendar = makeCalendar()
        let forward = CalendarNavigation.moved(from: date(2026, 12, 30), mode: .week, by: 1, calendar: calendar)
        #expect(forward.selectedDate == date(2027, 1, 6))
        #expect(forward.displayedMonth == date(2027, 1, 1))
        let back = CalendarNavigation.moved(from: date(2026, 3, 2), mode: .week, by: -1, calendar: calendar)
        #expect(back.selectedDate == date(2026, 2, 23))
        #expect(back.displayedMonth == date(2026, 2, 1))
    }

    @Test("按天移动，并且返回的都是零点")
    func dayStep() {
        let calendar = makeCalendar()
        let moved = CalendarNavigation.moved(from: date(2026, 10, 15, 17, 30), mode: .day, by: 1, calendar: calendar)
        #expect(moved.selectedDate == date(2026, 10, 16))
        #expect(calendar.startOfDay(for: moved.selectedDate) == moved.selectedDate)
    }

    @Test("周的 7 天按 firstWeekday 起排")
    func weekDates() {
        // 2026-10-15 是周四
        let sundayFirst = CalendarFormatting.weekDates(
            containing: date(2026, 10, 15, 9), calendar: makeCalendar(firstWeekday: 1))
        #expect(sundayFirst.count == 7)
        #expect(sundayFirst.first == date(2026, 10, 11))
        #expect(sundayFirst.last == date(2026, 10, 17))

        let mondayFirst = CalendarFormatting.weekDates(
            containing: date(2026, 10, 15, 9), calendar: makeCalendar(firstWeekday: 2))
        #expect(mondayFirst.first == date(2026, 10, 12))
        #expect(mondayFirst.last == date(2026, 10, 18))
    }

    @Test("周日为一周最后一天时，周日属于上一个周一起的周")
    func sundayBelongsToPreviousMondayWeek() {
        let week = CalendarFormatting.weekDates(
            containing: date(2026, 10, 18), calendar: makeCalendar(firstWeekday: 2))
        #expect(week.first == date(2026, 10, 12))
    }
}

// MARK: - 布局指标

@Suite("日历布局指标")
struct CalendarLayoutMetricsTests {

    /// 与视图层 `Limits.design` 同量级的测试值，数值自洽即可
    private let limits = CalendarLayoutMetrics.Limits(
        compactBelowWidth: 520,
        monthColumnFraction: 0.4,
        monthColumnMin: 300,
        monthColumnMax: 440,
        cellMinHeight: 30,
        cellMaxHeight: 72,
        lunarMinCellHeight: 40,
        lunarMinCellWidth: 34,
        weekNumberMinCellWidth: 40,
        gridChromeHeight: 80,
        summaryHeight: 100,
        summaryMinCellHeight: 36,
        rowSpacing: 2,
        horizontalPadding: 16,
        weekNumberColumn: 26,
        weekColumnsMinWidth: 560)

    private func metrics(
        _ width: CGFloat, _ height: CGFloat, rows: Int = 5, week: Bool = false, summary: Bool = true
    ) -> CalendarLayoutMetrics {
        .make(
            size: CGSize(width: width, height: height), rows: rows, wantsWeekNumber: week,
            wantsSummary: summary, limits: limits)
    }

    @Test("宽度分档：小于阈值单栏，否则双栏")
    func columnTiers() {
        #expect(metrics(519, 600).columns == .single)
        #expect(metrics(520, 600).columns == .double)
        #expect(metrics(400, 600).columns == .single)
    }

    @Test("双栏月历栏宽度按比例取并夹在范围内")
    func monthColumnWidthClamped() {
        #expect(metrics(600, 600).monthColumnWidth == 300, "600×0.4=240，抬到下限 300")
        #expect(metrics(900, 600).monthColumnWidth == 360)
        #expect(metrics(2000, 600).monthColumnWidth == 440, "再宽也不超过上限")
    }

    @Test("格高随窗口高度变化，夹在上下限之间")
    func cellHeightFollowsWindowHeight() {
        let tall = metrics(900, 1000, summary: false)
        let medium = metrics(900, 400, summary: false)
        #expect(tall.cellHeight == 72, "很高时顶到上限")
        #expect(medium.cellHeight < tall.cellHeight)
        #expect(medium.cellHeight >= 30)
        // 5 行：(400 - 80 - 4×2) / 5 = 62.4，比上限 72 小；再矮一点继续变小
        #expect(metrics(900, 300, summary: false).cellHeight < metrics(900, 360, summary: false).cellHeight)
    }

    @Test("过矮时收起农历小字，仍保持最小格高并允许月历栏滚动")
    func shortWindowDropsLunarAndScrolls() {
        let tiny = metrics(900, 200, summary: false)
        #expect(tiny.cellHeight == 30)
        #expect(!tiny.showsLunar)
        #expect(tiny.scrollsMonth, "连最小格高都放不下，必须滚动而不是裁剪")

        let roomy = metrics(900, 700, summary: false)
        #expect(roomy.showsLunar)
        #expect(!roomy.scrollsMonth)
    }

    @Test("放摘要会把格子压得太扁时先保格子，摘要收起")
    func summaryYieldsToCells() {
        // 高度 440：带摘要时 (440-80-100-8)/5 = 50.4 ≥ 36 → 保留
        #expect(metrics(900, 440).showsSummary)
        // 高度 300：带摘要时 (300-80-100-8)/5 = 22.4 < 36 → 收起，格子重新分到 (300-80-8)/5 = 42.4
        let squeezed = metrics(900, 300)
        #expect(!squeezed.showsSummary)
        #expect(squeezed.cellHeight > 40)
    }

    @Test("用户没开节假日时不预留摘要")
    func noSummaryWhenNotWanted() {
        #expect(!metrics(900, 900, summary: false).showsSummary)
    }

    @Test("周数列只在格子够宽时才出现")
    func weekNumberNeedsWidth() {
        #expect(metrics(900, 600, week: true).showsWeekNumberColumn)
        #expect(!metrics(900, 600, week: false).showsWeekNumberColumn)
        // 单栏 400 宽：(400-32-12)/7 ≈ 50 够宽；做一个更窄的
        let narrow = CalendarLayoutMetrics.make(
            size: CGSize(width: 300, height: 600), rows: 5, wantsWeekNumber: true, wantsSummary: false,
            limits: limits)
        #expect(!narrow.showsWeekNumberColumn, "格子不够宽时让位给日期数字")
    }

    @Test("单栏下格高只跟宽度走，不随窗口高度变化")
    func singleColumnIgnoresHeight() {
        let short = metrics(480, 300)
        let tall = metrics(480, 1200)
        #expect(short.columns == .single)
        #expect(short.cellHeight == tall.cellHeight)
        #expect(!short.scrollsMonth, "单栏整体滚动，月历本身不需要再滚")
    }

    @Test("周视图在窄宽度下改成纵向")
    func weekVerticalWhenNarrow() {
        #expect(metrics(500, 600).weekIsVertical)
        #expect(!metrics(560, 600).weekIsVertical)
    }

    @Test("零尺寸与 0 行不崩溃")
    func degenerateSizes() {
        let zero = CalendarLayoutMetrics.make(
            size: .zero, rows: 0, wantsWeekNumber: true, wantsSummary: true, limits: limits)
        #expect(zero.cellHeight >= limits.cellMinHeight)
        #expect(zero.columns == .single)
    }
}

// MARK: - 周 / 日布局

@Suite("日历周与日布局")
struct CalendarDayLayoutTests {

    private let calendar = makeCalendar()

    @Test("事件按天归并，跨天事件在每一天都出现，空日也有空数组")
    func eventsByDay() {
        let days = CalendarFormatting.weekDates(containing: date(2026, 10, 15), calendar: calendar)
        let multi = event("multi", date(2026, 10, 13, 22), date(2026, 10, 14, 2))
        let single = event("single", date(2026, 10, 15, 9), date(2026, 10, 15, 10))
        let grouped = CalendarDayLayout.eventsByDay([multi, single], days: days, calendar: calendar)

        #expect(grouped.count == 7)
        #expect(grouped[date(2026, 10, 13)]?.map(\.id) == ["multi"])
        #expect(grouped[date(2026, 10, 14)]?.map(\.id) == ["multi"])
        #expect(grouped[date(2026, 10, 15)]?.map(\.id) == ["single"])
        #expect(grouped[date(2026, 10, 16)]?.isEmpty == true)
    }

    @Test("恰好在午夜结束的事件不算进第二天")
    func endingAtMidnightExcluded() {
        let e = event("late", date(2026, 10, 15, 22), date(2026, 10, 16, 0))
        let grouped = CalendarDayLayout.eventsByDay([e], days: [date(2026, 10, 16)], calendar: calendar)
        #expect(grouped[date(2026, 10, 16)]?.isEmpty == true)
    }

    @Test("时间轴：全天事件单列，其余带分钟位置")
    func timelineSeparatesAllDay() {
        let day = date(2026, 10, 15)
        let timeline = CalendarDayLayout.timeline(
            events: [
                event("holiday", date(2026, 10, 15), date(2026, 10, 16), allDay: true),
                event("standup", date(2026, 10, 15, 9, 30), date(2026, 10, 15, 10, 0)),
            ], on: day, calendar: calendar)
        #expect(timeline.allDay.map(\.id) == ["holiday"])
        #expect(timeline.placed.count == 1)
        #expect(timeline.placed[0].startMinute == 9 * 60 + 30)
        #expect(timeline.placed[0].endMinute == 10 * 60)
        #expect(timeline.placed[0].columnCount == 1)
    }

    @Test("跨午夜事件裁到当天范围内")
    func clipsToDay() {
        let timeline = CalendarDayLayout.timeline(
            events: [event("overnight", date(2026, 10, 14, 23), date(2026, 10, 15, 2))],
            on: date(2026, 10, 15), calendar: calendar)
        #expect(timeline.placed[0].startMinute == 0)
        #expect(timeline.placed[0].endMinute == 2 * 60)
    }

    @Test("过短或零时长的事件撑到最短高度")
    func minimumDuration() {
        let timeline = CalendarDayLayout.timeline(
            events: [event("ping", date(2026, 10, 15, 8), date(2026, 10, 15, 8))],
            on: date(2026, 10, 15), calendar: calendar)
        #expect(timeline.placed[0].endMinute - timeline.placed[0].startMinute == CalendarDayLayout.minimumDurationMinutes)
    }

    @Test("重叠的事件并排分列，列数是该簇的最大并发数")
    func overlappingEventsShareColumns() {
        let timeline = CalendarDayLayout.timeline(
            events: [
                event("a", date(2026, 10, 15, 9), date(2026, 10, 15, 11)),
                event("b", date(2026, 10, 15, 10), date(2026, 10, 15, 12)),
                event("c", date(2026, 10, 15, 11), date(2026, 10, 15, 12, 30)),
            ], on: date(2026, 10, 15), calendar: calendar)
        let byID = Dictionary(uniqueKeysWithValues: timeline.placed.map { ($0.event.id, $0) })
        #expect(byID["a"]?.column == 0)
        #expect(byID["b"]?.column == 1)
        // c 在 a 结束后开始，回收 a 的列
        #expect(byID["c"]?.column == 0)
        #expect(timeline.placed.allSatisfy { $0.columnCount == 2 })
    }

    @Test("不重叠的事件各占整列，不被前一簇的列数拖累")
    func separateClustersDoNotShareWidth() {
        let timeline = CalendarDayLayout.timeline(
            events: [
                event("a", date(2026, 10, 15, 9), date(2026, 10, 15, 10)),
                event("b", date(2026, 10, 15, 9, 30), date(2026, 10, 15, 10, 30)),
                event("lonely", date(2026, 10, 15, 14), date(2026, 10, 15, 15)),
            ], on: date(2026, 10, 15), calendar: calendar)
        let lonely = timeline.placed.first { $0.event.id == "lonely" }
        #expect(lonely?.columnCount == 1)
        #expect(lonely?.column == 0)
    }

    @Test("初始滚动：有事件对准第一件事前一小时，今天无事件对准现在前两小时，其余 8 点")
    func initialScrollHour() {
        let withEvent = CalendarDayLayout.timeline(
            events: [event("x", date(2026, 10, 15, 14, 10), date(2026, 10, 15, 15))],
            on: date(2026, 10, 15), calendar: calendar)
        #expect(CalendarDayLayout.initialScrollHour(timeline: withEvent, isToday: true, nowMinute: 600) == 13)

        let empty = CalendarDayLayout.Timeline(allDay: [], placed: [])
        #expect(CalendarDayLayout.initialScrollHour(timeline: empty, isToday: true, nowMinute: 15 * 60) == 13)
        #expect(CalendarDayLayout.initialScrollHour(timeline: empty, isToday: false, nowMinute: 15 * 60) == 8)
        #expect(CalendarDayLayout.initialScrollHour(timeline: empty, isToday: true, nowMinute: 30) == 0)
    }
}

// MARK: - 缓存与区间查询

@Suite("日历缓存与区间查询")
struct CalendarCachingTests {

    @Test("黄历按日缓存：第二次读取不再计算")
    func almanacCacheHits() {
        let cache = AlmanacCache()
        let day = CivilDate(year: 2026, month: 10, day: 15)
        let first = cache.day(for: day)
        let second = cache.day(for: day)
        #expect(first == second)
        #expect(cache.computationCount == 1)
        _ = cache.day(for: day.adding(days: 1))
        #expect(cache.computationCount == 2)
        #expect(cache.day(for: day) == first, "缓存结果必须与直接计算一致")
        #expect(first == Almanac.day(for: day))
    }

    @Test("缓存到顶后整体清空，仍能给出正确结果")
    func cacheEvictsAtCapacity() {
        let cache = AlmanacCache()
        let start = CivilDate(year: 2026, month: 1, day: 1)
        for offset in 0..<(AlmanacCache.capacity + 5) {
            _ = cache.day(for: start.adding(days: offset))
        }
        #expect(cache.count <= AlmanacCache.capacity)
        #expect(cache.day(for: start) == Almanac.day(for: start))
    }

    @MainActor
    @Test("未授权时区间查询返回空，不触碰 EventKit")
    func rangeQueryRequiresAuthorization() {
        let service = CalendarService(accessState: .denied)
        let start = date(2026, 10, 12)
        #expect(service.events(from: start, to: date(2026, 10, 19)).isEmpty)
        #expect(service.events(on: start).isEmpty)
        // 起止颠倒同样安全
        #expect(service.events(from: date(2026, 10, 19), to: start).isEmpty)
    }
}
