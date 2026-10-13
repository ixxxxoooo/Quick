// CalendarFormatting.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 日历相关文本格式化与月历网格
enum CalendarFormatting {

    /// 农历日期文本
    ///
    /// 单独抽出来是因为它必须能在不启动 EventKit 的情况下被测试：
    /// 农历文本由「中国日历 + zh_CN」这组配置决定，配置被改动时输出会在界面上
    /// 悄悄变化，而不是编译报错。
    static func lunar(for date: Date) -> String {
        let chinese = Calendar(identifier: .chinese)
        let formatter = DateFormatter()
        formatter.calendar = chinese
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private static let lunarDayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
    ]

    private static let lunarMonthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月",
    ]

    /// 月历格子里的农历小字：初一显示月份（闰月加「闰」），其余显示「初三」「廿五」这样的日名
    static func lunarCellLabel(for date: Date) -> String {
        let chinese = Calendar(identifier: .chinese)
        let parts = chinese.dateComponents([.month, .day], from: date)
        guard let day = parts.day, (1...30).contains(day) else { return "" }
        if day == 1, let month = parts.month, (1...12).contains(month) {
            let leap = parts.isLeapMonth == true ? "闰" : ""
            return leap + lunarMonthNames[month - 1]
        }
        return lunarDayNames[day - 1]
    }

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
