// HolidayTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Synchronization
import Testing

@testable import PluginCalendar

private func civil(_ year: Int, _ month: Int, _ day: Int) -> CivilDate {
    CivilDate(year: year, month: month, day: day)
}

private func bundledCalendar() -> HolidayCalendar {
    HolidayCalendar(files: BundledHolidays.json.values.compactMap { HolidayYearFile.parse(Data($0.utf8)) })
}

private func makeStore(suite: String = "quick.test.holiday.\(UUID().uuidString)") -> HolidayStore {
    HolidayStore(suiteName: suite)
}

private func yearJSON(_ year: Int, days: [(String, String, Bool)]) -> Data {
    let items = days.map { #"{"name":"\#($0.0)","date":"\#($0.1)","isOffDay":\#($0.2)}"# }.joined(separator: ",")
    return Data(#"{"year":\#(year),"days":[\#(items)]}"#.utf8)
}

@Suite("内置节假日数据")
struct BundledHolidayTests {

    /// 期望值逐条取自国务院办公厅 2026 年放假通知（国办发明电〔2025〕7 号）
    @Test("2026 年的放假与调休和国务院通知一致")
    func year2026MatchesGovernmentNotice() throws {
        let calendar = bundledCalendar()
        let springFestival = try #require(calendar.periods.first { $0.name == "春节" && $0.start.year == 2026 })
        #expect(springFestival.start == civil(2026, 2, 15) && springFestival.end == civil(2026, 2, 23))
        #expect(springFestival.dayCount == 9)
        #expect(springFestival.makeupWorkdays == [civil(2026, 2, 14), civil(2026, 2, 28)])

        let national = try #require(calendar.periods.first { $0.name == "国庆节" && $0.start.year == 2026 })
        #expect(national.start == civil(2026, 10, 1) && national.end == civil(2026, 10, 7))
        #expect(national.makeupWorkdays == [civil(2026, 9, 20), civil(2026, 10, 10)])

        let labour = try #require(calendar.periods.first { $0.name == "劳动节" && $0.start.year == 2026 })
        #expect(labour.dayCount == 5 && labour.makeupWorkdays == [civil(2026, 5, 9)])

        let newYear = try #require(calendar.periods.first { $0.name == "元旦" && $0.start.year == 2026 })
        #expect(newYear.dayCount == 3 && newYear.makeupWorkdays == [civil(2026, 1, 4)])
    }

    @Test("2025 年国庆与中秋连放 8 天，两个名字合成一段")
    func year2025MergedHoliday() throws {
        let period = try #require(bundledCalendar().periods.first { $0.name == "国庆节、中秋节" })
        #expect(period.start == civil(2025, 10, 1) && period.end == civil(2025, 10, 8))
        #expect(period.makeupWorkdays == [civil(2025, 9, 28), civil(2025, 10, 11)])
    }

    @Test("每个内置年份都能解码、非空、日期全在本年")
    func everyBundledYearParses() {
        for (year, text) in BundledHolidays.json {
            let file = HolidayYearFile.parse(Data(text.utf8))
            #expect(file?.year == year)
        }
        #expect(BundledHolidays.json.keys.contains(2026))
    }
}

@Suite("节假日查询")
struct HolidayCalendarTests {

    @Test("放假日、补班日、普通日三种身份")
    func statuses() throws {
        let calendar = bundledCalendar()
        guard case .off(let period, let number)? = calendar.status(on: civil(2026, 10, 3)) else {
            Issue.record("2026-10-03 应是放假日")
            return
        }
        #expect(period.name == "国庆节" && number == 3)

        #expect(calendar.status(on: civil(2026, 10, 10)) == .makeupWorkday(name: "国庆节"))
        #expect(calendar.status(on: civil(2026, 10, 14)) == nil)
        #expect(calendar.status(on: civil(2026, 10, 11)) == nil, "普通周末没有角标")
    }

    @Test("多年合并，同一年后者覆盖前者")
    func laterFileWins() {
        let early = HolidayYearFile.parse(yearJSON(2030, days: [("甲", "2030-01-01", true)]))!
        let late = HolidayYearFile.parse(yearJSON(2030, days: [("乙", "2030-02-02", true)]))!
        let calendar = HolidayCalendar(files: [early, late])
        #expect(calendar.status(on: civil(2030, 1, 1)) == nil)
        #expect(calendar.status(on: civil(2030, 2, 2)) != nil)
        #expect(calendar.years == [2030])
    }

    @Test("近期假期：含正在放的，已结束的不算，数量受 limit 限制")
    func upcoming() {
        let calendar = bundledCalendar()
        let during = calendar.upcoming(from: civil(2026, 10, 3), limit: 3)
        #expect(during.first?.name == "国庆节", "正在放的假期排第一")
        #expect(calendar.upcoming(from: civil(2026, 10, 8), limit: 3).isEmpty, "已无后续已公布的安排")
        #expect(calendar.upcoming(from: civil(2026, 1, 1), limit: 2).count == 2)
        #expect(calendar.upcoming(from: civil(2026, 1, 1), limit: 0).isEmpty)
    }

    @Test("按月取与该月有交集的假期，跨月的假期两个月都算")
    func monthPeriods() {
        let calendar = bundledCalendar()
        #expect(calendar.periods(inYear: 2026, month: 2).map(\.name) == ["春节"])
        #expect(calendar.periods(inYear: 2026, month: 10).map(\.name) == ["国庆节"])
        #expect(calendar.periods(inYear: 2025, month: 10).map(\.name) == ["国庆节、中秋节"])
        #expect(calendar.periods(inYear: 2026, month: 8).isEmpty)
    }

    @Test("空数据与坏数据：不崩，也不产生任何假期")
    func emptyAndBadData() {
        #expect(HolidayCalendar.empty.periods.isEmpty)
        #expect(HolidayYearFile.parse(Data("not json".utf8)) == nil)
        #expect(HolidayYearFile.parse(yearJSON(2027, days: [])) == nil, "空 days 是「尚未公布」，不是数据")
        #expect(HolidayYearFile.parse(yearJSON(2027, days: [("x", "2026-01-01", true)])) == nil, "日期不在声明年份")
        #expect(HolidayYearFile.parse(yearJSON(2027, days: [("x", "2027-99-01", true)])) == nil)
    }
}

@Suite("节假日文案")
struct HolidayTextTests {

    private var national: HolidayPeriod {
        bundledCalendar().periods.first { $0.name == "国庆节" && $0.start.year == 2026 }!
    }

    @Test("日期范围：同月省略月份，跨月写全")
    func rangeText() {
        #expect(national.rangeText == "10月1日–7日")
        let crossMonth = HolidayPeriod(name: "x", start: civil(2026, 9, 30), end: civil(2026, 10, 2), makeupWorkdays: [])
        #expect(crossMonth.rangeText == "9月30日–10月2日")
        let single = HolidayPeriod(name: "x", start: civil(2026, 5, 1), end: civil(2026, 5, 1), makeupWorkdays: [])
        #expect(single.rangeText == "5月1日")
    }

    @Test("补班文案")
    func makeupText() {
        #expect(national.makeupText == "补班 9月20日、10月10日")
        #expect(HolidayPeriod(name: "x", start: civil(2026, 4, 4), end: civil(2026, 4, 6), makeupWorkdays: []).makeupText == nil)
    }

    @Test("倒数文案覆盖：未开始、明天、放假中、已结束")
    func countdown() {
        #expect(national.countdownText(from: civil(2026, 9, 14)) == "还有 17 天")
        #expect(national.countdownText(from: civil(2026, 9, 30)) == "明天开始")
        #expect(national.countdownText(from: civil(2026, 10, 2)) == "放假中 · 第 2 天 / 共 7 天")
        #expect(national.countdownText(from: civil(2026, 10, 8)) == "已结束")
        #expect(national.headline(from: civil(2026, 9, 14)) == "距国庆节还有 17 天")
        #expect(national.headline(from: civil(2026, 9, 30)) == "明天放假：国庆节")
    }

    @Test("角标与详情")
    func statusText() {
        #expect(HolidayStatus.off(national, dayNumber: 3).badge == "休")
        #expect(HolidayStatus.makeupWorkday(name: "国庆节").badge == "班")
        #expect(HolidayStatus.off(national, dayNumber: 3).detailText == "国庆节 · 放假第 3 天，共 7 天")
        #expect(HolidayStatus.makeupWorkday(name: "国庆节").detailText == "国庆节调休 · 需上班")
    }
}

@Suite("节假日联网更新")
struct HolidayStoreTests {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09 前后

    @Test("拿到有效的新数据后整年覆盖，并落盘供下次启动使用")
    func refreshReplacesYearAndPersists() async {
        let suite = "quick.test.holiday.\(UUID().uuidString)"
        let store = makeStore(suite: suite)
        let year = CivilDate(now).year
        let updated = await store.refreshIfNeeded(now: now) { target in
            target == year ? yearJSON(year, days: [("测试假", "\(year)-03-03", true)]) : yearJSON(target, days: [])
        }
        #expect(updated)
        #expect(store.calendar.status(on: civil(year, 3, 3)) != nil)

        let reopened = HolidayStore(suiteName: suite)
        #expect(reopened.calendar.status(on: civil(year, 3, 3)) != nil, "缓存应在重启后仍然可用")
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    @Test("网络失败：保留内置数据，不算更新，且短时间内不重试")
    func failureKeepsBundledAndThrottles() async {
        let store = makeStore()
        struct Offline: Error {}
        let before = store.calendar
        let updated = await store.refreshIfNeeded(now: now) { _ in throw Offline() }
        #expect(!updated)
        #expect(store.calendar == before)

        // 失败后的冷却期内不会再发请求
        let counter = Counter()
        _ = await store.refreshIfNeeded(now: now.addingTimeInterval(60)) { _ in
            counter.increment()
            throw Offline()
        }
        #expect(counter.value == 0)
        // 冷却期过后可以重试
        _ = await store.refreshIfNeeded(now: now.addingTimeInterval(HolidayStore.failureInterval + 1)) { _ in
            counter.increment()
            throw Offline()
        }
        #expect(counter.value == 2, "当年与次年各请求一次")
    }

    @Test("坏数据不会覆盖正确的内置数据")
    func badPayloadIsRejected() async {
        let store = makeStore()
        let before = store.calendar
        let updated = await store.refreshIfNeeded(now: now) { _ in Data("<html>502</html>".utf8) }
        #expect(!updated)
        #expect(store.calendar == before)
    }

    @Test("成功后一周内不再联网，force 可以跳过间隔")
    func successInterval() async {
        let store = makeStore()
        let counter = Counter()
        let year = CivilDate(now).year
        let fetch: @Sendable (Int) async throws -> Data = { target in
            counter.increment()
            return yearJSON(target, days: target == year ? [("甲", "\(target)-05-05", true)] : [])
        }
        _ = await store.refreshIfNeeded(now: now, fetch: fetch)
        let first = counter.value
        _ = await store.refreshIfNeeded(now: now.addingTimeInterval(3600), fetch: fetch)
        #expect(counter.value == first, "一周内不再请求")
        _ = await store.refreshIfNeeded(now: now.addingTimeInterval(3600), force: true, fetch: fetch)
        #expect(counter.value == first * 2)
        #expect(store.lastSuccess != nil)
    }
}

/// 线程安全计数器：`fetch` 闭包是 `@Sendable`，不能捕获可变局部变量
private final class Counter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

@MainActor
@Suite("日历搜索：节假日 / 节气 / 农历")
struct CalendarSearchTests {

    private func plugin(now: Date) -> CalendarPlugin {
        CalendarPlugin(
            service: CalendarService(accessState: .authorized),
            holidayStore: makeStore(),
            now: { now })
    }

    @Test("搜「节假日」返回近期假期与倒数，而不是今日无日程")
    func holidayQuery() async {
        let items = await plugin(now: date(2026, 9, 28)).dynamicSearch(query: "节假日")
        #expect(items.first?.title == "国庆节 · 还有 3 天")
        #expect(items.first?.subtitle == "10月1日–7日 · 共 7 天 · 补班 9月20日、10月10日")
        #expect(!items.contains { $0.id == "calendar.today" })
    }

    @Test("没有已公布的后续安排时给出说明条目")
    func holidayQueryWithoutData() async {
        let items = await plugin(now: date(2026, 12, 1)).dynamicSearch(query: "假期")
        #expect(items.count == 1)
        #expect(items.first?.id == "calendar.holiday.none")
    }

    @Test("搜「节气」给出下一个节气，当天交节显示今天")
    func solarTermQuery() async {
        let upcoming = await plugin(now: date(2026, 10, 14)).dynamicSearch(query: "节气")
        #expect(upcoming.first?.title == "下一个节气：霜降")
        #expect(upcoming.first?.subtitle == "10月23日 · 还有 9 天")
        let today = await plugin(now: date(2026, 10, 23)).dynamicSearch(query: "节气")
        #expect(today.first?.title == "今天是霜降")
    }

    @Test("搜「农历」给出今天的农历与干支")
    func lunarQuery() async {
        let items = await plugin(now: date(2026, 2, 17)).dynamicSearch(query: "农历")
        #expect(items.first?.title == "今天 · 农历正月初一")
        #expect(items.first?.subtitle?.contains("丙午年") == true)
        #expect(items.first?.subtitle?.contains("春节") == true)
    }

    @Test("这几类结果不依赖日历权限")
    func independentOfCalendarAccess() async {
        let denied = CalendarPlugin(
            service: CalendarService(accessState: .denied), holidayStore: makeStore(),
            now: { date(2026, 9, 14) })
        #expect(await denied.dynamicSearch(query: "节假日").first?.id.hasPrefix("calendar.holiday") == true)
    }
}
