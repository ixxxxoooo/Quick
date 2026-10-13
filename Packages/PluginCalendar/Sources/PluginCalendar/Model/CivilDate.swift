// CivilDate.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一个公历日期（年月日，没有时刻也没有时区）
///
/// 节假日、节气、干支都是「某一天」的属性，用 `Date` 表达会把时区带进来：同一个 `Date`
/// 在两个时区可能是两天。所以 Model 层统一用它，只在边界上与 `Date` 互转。
/// 儒略日数让「加减天数、星期、干支日」都变成整数运算，不依赖 `Calendar`。
struct CivilDate: Hashable, Comparable, Sendable {

    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// 取 `date` 在 `calendar` 时区里的公历年月日
    init(_ date: Date, calendar: Calendar = .current) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// 解析 `yyyy-MM-dd`；格式或数值不合法返回 `nil`
    init?(isoString: String) {
        let parts = isoString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    // MARK: - 儒略日

    /// 儒略日数（整数日，格里历）
    var julianDay: Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    init(julianDay: Int) {
        let a = julianDay + 32044
        let b = (4 * a + 3) / 146097
        let c = a - 146097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        self.init(
            year: 100 * b + d - 4800 + m / 10,
            month: m + 3 - 12 * (m / 10),
            day: e - (153 * m + 2) / 5 + 1)
    }

    /// 前后推 `days` 天（可为负）
    func adding(days: Int) -> CivilDate {
        CivilDate(julianDay: julianDay + days)
    }

    /// 到 `other` 还有几天（`other` 在后为正）
    func days(until other: CivilDate) -> Int {
        other.julianDay - julianDay
    }

    /// 星期：0 = 周日 … 6 = 周六
    var weekday: Int {
        (julianDay + 1) % 7
    }

    /// 这个月有几天
    var daysInMonth: Int {
        let nextFirst = CivilDate(year: month == 12 ? year + 1 : year, month: month == 12 ? 1 : month + 1, day: 1)
        return CivilDate(year: year, month: month, day: 1).days(until: nextFirst)
    }

    static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// `3月5日` 这样的短文本
    var monthDayText: String {
        "\(month)月\(day)日"
    }
}
