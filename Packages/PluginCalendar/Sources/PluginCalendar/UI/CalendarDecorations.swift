// CalendarDecorations.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 三个视图共用的「每一天挂什么」：休 / 班、黄历、有日程的小圆点
///
/// 一个值对象，由 `CalendarView` 在状态变化时重建；子视图只读它，
/// 不各自去碰 `HolidayStore` 或重复计算黄历（黄历走 `AlmanacCache`）。
struct CalendarDecorations {
    let holidays: HolidayCalendar
    let showHolidays: Bool
    let showAlmanac: Bool
    /// 月历里有日程的日子（每天零点）
    let markedDays: Set<Date>
    let calendar: Calendar

    func almanac(for civil: CivilDate) -> AlmanacDay {
        AlmanacCache.shared.day(for: civil)
    }

    func status(on civil: CivilDate) -> HolidayStatus? {
        showHolidays ? holidays.status(on: civil) : nil
    }

    func hasEvents(on date: Date) -> Bool {
        markedDays.contains(calendar.startOfDay(for: date))
    }
}
