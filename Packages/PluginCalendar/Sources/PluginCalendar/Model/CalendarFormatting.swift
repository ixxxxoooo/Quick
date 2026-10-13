// CalendarFormatting.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 月历网格与周数（农历、节气、节日在 `Almanac`）
enum CalendarFormatting {

    /// 一年中的第几周
    ///
    /// 用传入日历的 `weekOfYear`，所以「周从周几开始、第一周怎么算」跟随系统区域设置，
    /// 和系统日历 App 的周数一致。
    static func weekNumber(for date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekOfYear, from: date)
    }

    // MARK: - 月历网格

    /// 月历的一格
    struct DayCell: Identifiable, Equatable, Sendable {
        /// 这一天的零点；补位的空格为 `nil`
        let date: Date?
        let id: Int
    }

    /// 月历的一行（一周）
    struct WeekRow: Identifiable, Equatable, Sendable {
        let id: Int
        /// 这一行的周数（取该行第一个有效日期）；整行为空时为 `nil`
        let weekNumber: Int?
        let cells: [DayCell]
    }

    /// 生成包含 `month` 的整月网格：行 = 周，列 = 星期，首列由 `calendar.firstWeekday` 决定
    static func monthGrid(containing month: Date, calendar: Calendar = .current) -> [WeekRow] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
            let dayCount = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }

        let firstWeekdayOfMonth = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekdayOfMonth - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            days.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        while days.count % 7 != 0 { days.append(nil) }

        return stride(from: 0, to: days.count, by: 7).map { start in
            let slice = Array(days[start..<start + 7])
            let cells = slice.enumerated().map { DayCell(date: $1, id: start + $0) }
            let week = slice.compactMap { $0 }.first.map { weekNumber(for: $0, calendar: calendar) }
            return WeekRow(id: start / 7, weekNumber: week, cells: cells)
        }
    }

    /// 表头的星期缩写，按 `firstWeekday` 起排
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}
