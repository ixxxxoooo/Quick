// AlmanacTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginCalendar

private func civil(_ year: Int, _ month: Int, _ day: Int) -> CivilDate {
    CivilDate(year: year, month: month, day: day)
}

@Suite("公历日期值类型")
struct CivilDateTests {

    @Test("儒略日往返无损，跨闰年与世纪")
    func julianRoundTrip() {
        for date in [civil(1900, 3, 1), civil(2000, 2, 29), civil(2024, 12, 31), civil(2100, 1, 1)] {
            #expect(CivilDate(julianDay: date.julianDay) == date)
        }
        #expect(civil(2000, 1, 1).julianDay == 2_451_545)
    }

    @Test("加减天数跨月跨年")
    func addingDays() {
        #expect(civil(2026, 12, 31).adding(days: 1) == civil(2027, 1, 1))
        #expect(civil(2024, 3, 1).adding(days: -1) == civil(2024, 2, 29))
        #expect(civil(2026, 10, 14).days(until: civil(2026, 10, 1)) == -13)
    }

    @Test("星期与月天数")
    func weekdayAndMonthLength() {
        #expect(civil(2026, 10, 1).weekday == 4, "2026-10-01 是周四")
        #expect(civil(2026, 2, 15).weekday == 0, "2026-02-15 是周日")
        #expect(civil(2024, 2, 1).daysInMonth == 29)
        #expect(civil(2026, 2, 1).daysInMonth == 28)
        #expect(civil(2026, 12, 1).daysInMonth == 31)
    }

    @Test("解析 ISO 日期，坏格式返回 nil")
    func parsesIsoStrings() {
        #expect(CivilDate(isoString: "2026-10-01") == civil(2026, 10, 1))
        #expect(CivilDate(isoString: "2026-13-01") == nil)
        #expect(CivilDate(isoString: "abc") == nil)
        #expect(CivilDate(isoString: "2026-10") == nil)
    }
}

@Suite("24 节气")
struct SolarTermTests {

    /// 期望值来自香港天文台公历农历对照表（权威数据），不是对表本身的复述
    @Test("2024–2026 的关键节气", arguments: [
        (2024, 2, 4, "立春"), (2024, 3, 20, "春分"), (2024, 12, 21, "冬至"),
        (2025, 2, 3, "立春"), (2025, 6, 21, "夏至"), (2025, 10, 8, "寒露"),
        (2026, 2, 4, "立春"), (2026, 3, 20, "春分"), (2026, 4, 5, "清明"),
        (2026, 6, 21, "夏至"), (2026, 9, 23, "秋分"), (2026, 10, 23, "霜降"), (2026, 12, 22, "冬至"),
    ])
    func knownTerms(year: Int, month: Int, day: Int, name: String) throws {
        let index = try #require(SolarTerm.index(on: civil(year, month, day)))
        #expect(SolarTerm.names[index] == name)
    }

    @Test("每年恰好 24 个节气，且逐个递增")
    func twentyFourAscending() throws {
        for year in [1901, 1950, 2000, 2026, 2100] {
            let dates = try (0..<24).map { try #require(SolarTerm.date(year: year, index: $0)) }
            #expect(dates == dates.sorted())
            #expect(Set(dates).count == 24)
        }
    }

    @Test("数据范围之外没有节气")
    func outOfRange() {
        #expect(SolarTerm.date(year: 1900, index: 0) == nil)
        #expect(SolarTerm.date(year: 2101, index: 0) == nil)
        #expect(SolarTerm.date(year: 2026, index: 24) == nil)
    }

    @Test("下一个节气：当天交节就是今天，跨年取明年小寒")
    func nextTerm() throws {
        let sameDay = try #require(SolarTerm.next(onOrAfter: civil(2026, 10, 23)))
        #expect(sameDay.name == "霜降" && sameDay.date == civil(2026, 10, 23))
        let wrap = try #require(SolarTerm.next(onOrAfter: civil(2026, 12, 23)))
        #expect(wrap.name == "小寒" && wrap.date.year == 2027)
    }
}

@Suite("干支与生肖")
struct GanzhiTests {

    /// 2000-01-01 戊午、2024-01-01 甲子、1949-10-01 甲子都是公认的对照点
    @Test("日柱对照点")
    func dayPillar() {
        #expect(Almanac.day(for: civil(2000, 1, 1)).dayGanzhi == "戊午")
        #expect(Almanac.day(for: civil(2024, 1, 1)).dayGanzhi == "甲子")
        #expect(Almanac.day(for: civil(1949, 10, 1)).dayGanzhi == "甲子")
    }

    @Test("六十甲子循环，负数与超界取模")
    func cycle() {
        #expect(Almanac.ganzhi(0) == "甲子")
        #expect(Almanac.ganzhi(59) == "癸亥")
        #expect(Almanac.ganzhi(60) == "甲子")
        #expect(Almanac.ganzhi(-1) == "癸亥")
    }

    @Test("年柱与生肖按农历年，春节前仍属上一年")
    func yearPillarFollowsLunarYear() {
        let afterNewYear = Almanac.day(for: civil(2026, 2, 17))
        #expect(afterNewYear.yearGanzhi == "丙午" && afterNewYear.zodiac == "马")
        let beforeNewYear = Almanac.day(for: civil(2026, 2, 16))
        #expect(beforeNewYear.yearGanzhi == "乙巳" && beforeNewYear.zodiac == "蛇")
        #expect(Almanac.day(for: civil(2024, 2, 10)).zodiac == "龙")
    }

    /// 月柱以「节」换月：2024-02-04 立春当天起是丙寅月（甲辰年，五虎遁起丙）
    @Test("月柱按节气换月，月干由年干推出")
    func monthPillar() {
        #expect(Almanac.day(for: civil(2024, 2, 3)).monthGanzhi == "乙丑")
        #expect(Almanac.day(for: civil(2024, 2, 4)).monthGanzhi == "丙寅")
        #expect(Almanac.day(for: civil(2026, 10, 14)).monthGanzhi == "戊戌")
        #expect(Almanac.day(for: civil(2026, 1, 6)).monthGanzhi == "己丑", "小寒之后、立春之前仍属丑月，年干取上一个立春年")
    }

    @Test("节气表之外没有月柱，但日柱与农历照常")
    func outsideTable() {
        let day = Almanac.day(for: civil(1890, 6, 1))
        #expect(day.monthGanzhi == nil)
        #expect(!day.dayGanzhi.isEmpty)
        #expect(day.ganzhiText.hasSuffix("日"))
    }

    @Test("干支文本拼成「丙午年 戊戌月 辛酉日」的形状")
    func ganzhiText() {
        let text = Almanac.day(for: civil(2026, 10, 14)).ganzhiText
        #expect(text.hasPrefix("丙午年 戊戌月 "))
        #expect(text.hasSuffix("日"))
    }
}

@Suite("农历与节日")
struct FestivalTests {

    @Test("农历文本与格子小字：初一显示月名，闰月带「闰」")
    func lunarLabels() {
        let springFestival = Almanac.day(for: civil(2026, 2, 17))
        #expect(springFestival.lunarText == "正月初一" && springFestival.lunarLabel == "正月")
        #expect(Almanac.day(for: civil(2026, 2, 19)).lunarLabel == "初三")
        #expect(Almanac.day(for: civil(2026, 9, 21)).lunarText == "八月十一")
        let leap = Almanac.day(for: civil(2025, 7, 25))
        #expect(leap.isLeapMonth && leap.lunarText == "闰六月初一" && leap.lunarLabel == "闰六月")
        #expect(Almanac.day(for: civil(2000, 1, 1)).lunarText == "冬月廿五")
    }

    @Test("传统节日落在对的那一天", arguments: [
        (2026, 2, 16, "除夕"), (2026, 2, 17, "春节"), (2026, 3, 3, "元宵节"), (2026, 6, 19, "端午节"),
        (2026, 8, 19, "七夕"), (2026, 9, 25, "中秋节"), (2026, 10, 18, "重阳节"),
        (2024, 2, 9, "除夕"), (2025, 1, 28, "除夕"),
    ])
    func traditionalFestivals(year: Int, month: Int, day: Int, name: String) {
        #expect(Almanac.day(for: civil(year, month, day)).festivals.contains(name))
    }

    @Test("闰月里的同名日子不是节日")
    func leapMonthIsNotFestival() {
        // 2025 闰六月，没有「闰五月初五」这类需要避开的情况；这里钉住闰月初一不被当成春节
        #expect(Almanac.day(for: civil(2025, 7, 25)).festivals.isEmpty)
    }

    @Test("公历节日与按周规则推出的母亲节、父亲节")
    func gregorianFestivals() {
        #expect(Almanac.day(for: civil(2026, 10, 1)).festivals.contains("国庆节"))
        #expect(Almanac.day(for: civil(2026, 5, 10)).festivals.contains("母亲节"))
        #expect(Almanac.day(for: civil(2026, 6, 21)).festivals.contains("父亲节"))
        #expect(!Almanac.day(for: civil(2026, 5, 17)).festivals.contains("母亲节"))
    }

    @Test("清明既是节气也是节日，格子小字取节日")
    func qingming() {
        let day = Almanac.day(for: civil(2026, 4, 5))
        #expect(day.solarTerm == "清明" && day.festivals.contains("清明节"))
        #expect(day.cellLabel == "清明节")
    }

    @Test("格子小字优先级：节日 > 节气 > 农历")
    func cellLabelPriority() {
        #expect(Almanac.day(for: civil(2026, 9, 25)).cellLabel == "中秋节")
        #expect(Almanac.day(for: civil(2026, 10, 23)).cellLabel == "霜降")
        #expect(Almanac.day(for: civil(2026, 10, 14)).cellLabel == "初五")
    }

    @Test("近期节日：按日期升序、清明不重复、当天算今天")
    func upcomingObservances() {
        let items = Almanac.upcomingObservances(from: civil(2026, 10, 14), limit: 3)
        #expect(items.map(\.name) == ["重阳节", "霜降", "立冬"])
        #expect(items.first?.countdownText(from: civil(2026, 10, 14)) == "还有 4 天")
        #expect(items.first?.countdownText(from: civil(2026, 10, 18)) == "今天")
        #expect(items.first?.countdownText(from: civil(2026, 10, 17)) == "明天")

        let april = Almanac.upcomingObservances(from: civil(2026, 4, 4), limit: 5).filter { $0.date == civil(2026, 4, 5) }
        #expect(april.map(\.name) == ["清明节"])
    }
}
