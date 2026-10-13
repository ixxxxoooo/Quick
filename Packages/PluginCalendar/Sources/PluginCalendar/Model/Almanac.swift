// Almanac.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 24 节气
///
/// 日期查 `SolarTermTable`（权威数据，范围 1901–2100），不用公式推算：
/// 交接时刻离午夜只差几分钟时，任何天文近似都会差一天。
enum SolarTerm {

    /// 小寒起、冬至止，共 24 个
    static let names = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨", "立夏", "小满", "芒种", "夏至",
        "小暑", "大暑", "立秋", "处暑", "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至",
    ]

    private static let digitValues: [Character: Int] = Dictionary(
        uniqueKeysWithValues: SolarTermTable.digits.enumerated().map { ($1, $0) })

    /// 第 `index` 个节气（0 = 小寒）在 `year` 年的日期；年份超出数据范围返回 `nil`
    static func date(year: Int, index: Int) -> CivilDate? {
        let row = year - SolarTermTable.firstYear
        guard (0..<24).contains(index), SolarTermTable.rows.indices.contains(row) else { return nil }
        let characters = Array(SolarTermTable.rows[row])
        guard let day = digitValues[characters[index]] else { return nil }
        return CivilDate(year: year, month: index / 2 + 1, day: day)
    }

    /// 从 `date` 起（含当天）的下一个节气；数据范围之外返回 `nil`
    static func next(onOrAfter date: CivilDate) -> (name: String, date: CivilDate)? {
        for year in [date.year, date.year + 1] {
            for index in 0..<24 {
                if let candidate = Self.date(year: year, index: index), candidate >= date {
                    return (names[index], candidate)
                }
            }
        }
        return nil
    }

    /// 恰好在 `date` 这一天交节气的下标；不是节气日返回 `nil`
    static func index(on date: CivilDate) -> Int? {
        for index in [(date.month - 1) * 2, (date.month - 1) * 2 + 1]
        where Self.date(year: date.year, index: index) == date {
            return index
        }
        return nil
    }
}

/// 某一天的农历 / 干支 / 节气 / 节日信息
///
/// 纯值类型，由 `Almanac.day(for:)` 一次算出。黄历在这里是精简版：干支、生肖、节气、节日，
/// 不含宜忌 —— 宜忌各来源结果不一，没有公认的标准答案。
struct AlmanacDay: Equatable, Sendable {

    let date: CivilDate
    /// 农历月（1–12）与日（1–30）
    let lunarMonth: Int
    let lunarDay: Int
    let isLeapMonth: Bool
    /// 农历年的干支，如「丙午」
    let yearGanzhi: String
    /// 生肖，如「马」
    let zodiac: String
    /// 月柱（按节气换月，不是农历月）；年份超出节气表范围时为 `nil`
    let monthGanzhi: String?
    let dayGanzhi: String
    /// 当天交节气时的名称
    let solarTerm: String?
    /// 当天的节日，传统节日在前
    let festivals: [String]

    /// 「八月十一」「闰六月初三」
    var lunarText: String {
        Almanac.monthName(lunarMonth, isLeap: isLeapMonth) + Almanac.dayName(lunarDay)
    }

    /// 「丙午年 戊戌月 辛酉日」
    var ganzhiText: String {
        [yearGanzhi + "年", monthGanzhi.map { $0 + "月" }, dayGanzhi + "日"].compactMap { $0 }.joined(separator: " ")
    }

    /// 农历日名；初一显示月名（闰月带「闰」）
    var lunarLabel: String {
        lunarDay == 1 ? Almanac.monthName(lunarMonth, isLeap: isLeapMonth) : Almanac.dayName(lunarDay)
    }

    /// 月历格子里的小字：节日 > 节气 > 农历日
    var cellLabel: String {
        festivals.first ?? solarTerm ?? lunarLabel
    }

    /// 当天值得点出来的名字（节日与节气），详情卡用
    var highlights: [String] {
        festivals + (solarTerm.map { [$0] } ?? [])
    }
}

/// 精简黄历：农历、干支、生肖、节气、公历与农历节日
enum Almanac {

    // MARK: - 名称表

    private static let stems = Array("甲乙丙丁戊己庚辛壬癸")
    private static let branches = Array("子丑寅卯辰巳午未申酉戌亥")
    private static let zodiacs = Array("鼠牛虎兔龙蛇马羊猴鸡狗猪")

    private static let dayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
    ]

    private static let monthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月",
    ]

    static func dayName(_ day: Int) -> String {
        dayNames.indices.contains(day - 1) ? dayNames[day - 1] : ""
    }

    static func monthName(_ month: Int, isLeap: Bool) -> String {
        guard monthNames.indices.contains(month - 1) else { return "" }
        return (isLeap ? "闰" : "") + monthNames[month - 1]
    }

    // MARK: - 干支

    /// 六十甲子第 `index` 位（0 = 甲子），负数与超界取模
    static func ganzhi(_ index: Int) -> String {
        let n = ((index % 60) + 60) % 60
        return String(stems[n % 10]) + String(branches[n % 12])
    }

    /// 日柱：以儒略日推算，2000-01-01 是戊午（第 54 位）
    static func dayGanzhiIndex(_ date: CivilDate) -> Int {
        ((date.julianDay + 49) % 60 + 60) % 60
    }

    /// 月柱：以「节」换月，月干由当年（立春为界）的年干按「五虎遁」推出
    ///
    /// - Returns: 六十甲子下标；`date` 所在年份超出节气表范围时为 `nil`
    static func monthGanzhiIndex(_ date: CivilDate) -> Int? {
        guard let jie = lastJie(onOrBefore: date), let lichun = SolarTerm.date(year: date.year, index: 2)
        else { return nil }
        let branchOffset = jie.index == 0 ? 11 : (jie.index - 2) / 2
        let lichunYear = date < lichun ? date.year - 1 : date.year
        let yearStem = ((lichunYear - 4) % 10 + 10) % 10
        let tigerStem = (yearStem % 5) * 2 + 2
        let stem = (tigerStem + branchOffset) % 10
        let branch = (2 + branchOffset) % 12
        return (0..<60).first { $0 % 10 == stem && $0 % 12 == branch }
    }

    /// 离 `date` 最近的、不晚于它的「节」（小寒、立春、惊蛰……共 12 个）
    private static func lastJie(onOrBefore date: CivilDate) -> (index: Int, date: CivilDate)? {
        for year in [date.year, date.year - 1] {
            for index in stride(from: 22, through: 0, by: -2) {
                if let candidate = SolarTerm.date(year: year, index: index), candidate <= date {
                    return (index, candidate)
                }
            }
        }
        return nil
    }

    // MARK: - 农历换算

    /// 农历要用「北京时间的一天」才对：固定时区、正午取样，避免换日线边缘与系统时区干扰
    private static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt

    private static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()

    private static let chinese: Calendar = {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = timeZone
        return calendar
    }()

    struct Lunar: Equatable, Sendable {
        /// 六十甲子年序（1 = 甲子年）
        let cycleYear: Int
        let month: Int
        let day: Int
        let isLeapMonth: Bool
    }

    static func lunar(of date: CivilDate) -> Lunar? {
        let components = DateComponents(year: date.year, month: date.month, day: date.day, hour: 12)
        guard let noon = gregorian.date(from: components) else { return nil }
        let parts = chinese.dateComponents([.year, .month, .day], from: noon)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return Lunar(cycleYear: year, month: month, day: day, isLeapMonth: parts.isLeapMonth == true)
    }

    // MARK: - 节日

    private static let gregorianFestivals: [Int: String] = [
        101: "元旦", 214: "情人节", 308: "妇女节", 312: "植树节", 401: "愚人节", 501: "劳动节",
        504: "青年节", 601: "儿童节", 701: "建党节", 801: "建军节", 910: "教师节", 1001: "国庆节",
        1224: "平安夜", 1225: "圣诞节",
    ]

    private static let lunarFestivals: [Int: String] = [
        101: "春节", 115: "元宵节", 202: "龙抬头", 505: "端午节", 707: "七夕", 715: "中元节",
        815: "中秋节", 909: "重阳节", 1208: "腊八节", 1223: "小年",
    ]

    /// 当天的节日：农历传统节日在前，公历节日在后，清明与母亲节、父亲节按规则推出
    private static func festivals(on date: CivilDate, lunar: Lunar?, isSolarTermQingming: Bool) -> [String] {
        var names: [String] = []
        if let lunar, !lunar.isLeapMonth {
            if let name = lunarFestivals[lunar.month * 100 + lunar.day] { names.append(name) }
            if lunar.month == 12, lunar.day >= 29, let next = lunarTomorrow(after: date), next.month == 1, next.day == 1 {
                names.append("除夕")
            }
        }
        if isSolarTermQingming { names.append("清明节") }
        if let name = gregorianFestivals[date.month * 100 + date.day] { names.append(name) }
        if date.weekday == 0 {
            let nth = (date.day - 1) / 7 + 1
            if date.month == 5, nth == 2 { names.append("母亲节") }
            if date.month == 6, nth == 3 { names.append("父亲节") }
        }
        return names
    }

    private static func lunarTomorrow(after date: CivilDate) -> Lunar? {
        lunar(of: date.adding(days: 1))
    }

    // MARK: - 入口

    /// 算出 `date` 这一天的全部黄历信息
    ///
    /// 农历换算失败（极端年份）时按公历日期兜底：农历字段为 0、名称为空，调用方不会崩。
    static func day(for date: CivilDate) -> AlmanacDay {
        let lunar = lunar(of: date)
        let cycleYear = lunar?.cycleYear ?? 1
        let termIndex = SolarTerm.index(on: date)
        return AlmanacDay(
            date: date,
            lunarMonth: lunar?.month ?? 0,
            lunarDay: lunar?.day ?? 0,
            isLeapMonth: lunar?.isLeapMonth ?? false,
            yearGanzhi: ganzhi(cycleYear - 1),
            zodiac: String(zodiacs[(cycleYear - 1) % 12]),
            monthGanzhi: monthGanzhiIndex(date).map(ganzhi),
            dayGanzhi: ganzhi(dayGanzhiIndex(date)),
            solarTerm: termIndex.map { SolarTerm.names[$0] },
            festivals: festivals(on: date, lunar: lunar, isSolarTermQingming: termIndex == 6))
    }

    // MARK: - 近期节日

    /// 一个即将到来的节日或节气
    struct Observance: Equatable, Sendable {
        let name: String
        let date: CivilDate
        let isSolarTerm: Bool

        /// 相对 `today` 的倒数：「今天」「明天」「还有 12 天」
        func countdownText(from today: CivilDate) -> String {
            switch today.days(until: date) {
            case 0: "今天"
            case 1: "明天"
            case let days: "还有 \(days) 天"
            }
        }
    }

    /// `date` 起（含当天）`horizon` 天内的节日与节气，按日期升序，最多 `limit` 个
    ///
    /// 清明这种「节气与节日同名」的日子只出一条（节日）。没有官方放假安排的节日也在内：
    /// 官方安排通常年底才公布，那之前右栏不该是一片空白。
    static func upcomingObservances(from date: CivilDate, limit: Int, horizon: Int = 120) -> [Observance] {
        var result: [Observance] = []
        for offset in 0..<horizon where result.count < limit {
            let current = date.adding(days: offset)
            let almanac = day(for: current)
            for name in almanac.festivals {
                result.append(Observance(name: name, date: current, isSolarTerm: false))
            }
            if let term = almanac.solarTerm, !almanac.festivals.contains(where: { $0.hasPrefix(term) }) {
                result.append(Observance(name: term, date: current, isSolarTerm: true))
            }
        }
        return Array(result.prefix(limit))
    }
}
