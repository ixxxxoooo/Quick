// HolidayCalendar.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一年的法定节假日安排（holiday-cn 年度 JSON 的格式，也是国务院放假通知的结构化形式）
///
/// 只列出「与默认周末作息不同」的日子：`isOffDay == true` 是放假（含落在周末的法定假日），
/// `false` 是调休补班。没出现的日子，周末休息、工作日上班。
struct HolidayYearFile: Decodable, Sendable, Equatable {

    struct Day: Decodable, Sendable, Equatable {
        let name: String
        let date: String
        let isOffDay: Bool
    }

    let year: Int
    let days: [Day]

    /// 解码并校验：年份必须合法、至少有一天，每个日期都要落在声明的年份里
    ///
    /// 联网拿到的是外部数据，不能信：空数据（通知还没公布时的占位）、错年份、坏日期一律拒收，
    /// 否则一份坏数据会把内置的正确数据覆盖掉。
    static func parse(_ data: Data) -> HolidayYearFile? {
        guard let file = try? JSONDecoder().decode(HolidayYearFile.self, from: data),
            (1900...2200).contains(file.year), !file.days.isEmpty,
            file.days.allSatisfy({ CivilDate(isoString: $0.date)?.year == file.year })
        else { return nil }
        return file
    }
}

/// 一段连续的法定假期（例如「春节 2月15日–23日，共 9 天」）
struct HolidayPeriod: Equatable, Sendable {
    let name: String
    let start: CivilDate
    let end: CivilDate
    /// 为这段假期调休的补班日（周末上班），按日期升序
    let makeupWorkdays: [CivilDate]

    var dayCount: Int { start.days(until: end) + 1 }

    /// `date` 是这段假期的第几天（从 1 起）；不在假期内返回 `nil`
    func dayNumber(of date: CivilDate) -> Int? {
        (start...end).contains(date) ? start.days(until: date) + 1 : nil
    }
}

/// 某一天在法定节假日安排里的身份
enum HolidayStatus: Equatable, Sendable {
    /// 放假；`dayNumber` 是这段假期的第几天
    case off(HolidayPeriod, dayNumber: Int)
    /// 为某个假期调休的补班日
    case makeupWorkday(name: String)
}

/// 法定节假日与调休查询（纯逻辑，不碰系统日历）
struct HolidayCalendar: Sendable, Equatable {

    private let offDays: [CivilDate: HolidayPeriod]
    private let workdays: [CivilDate: String]
    /// 按开始日期升序
    let periods: [HolidayPeriod]
    /// 有数据的年份
    let years: Set<Int>

    static let empty = HolidayCalendar(files: [])

    /// 多年数据合并；同一年出现多份时，后面的覆盖前面的
    init(files: [HolidayYearFile]) {
        var byYear: [Int: HolidayYearFile] = [:]
        for file in files { byYear[file.year] = file }
        years = Set(byYear.keys)

        var off: [(date: CivilDate, name: String)] = []
        var work: [(date: CivilDate, name: String)] = []
        for file in byYear.values {
            for day in file.days {
                guard let date = CivilDate(isoString: day.date) else { continue }
                if day.isOffDay { off.append((date, day.name)) } else { work.append((date, day.name)) }
            }
        }
        off.sort { $0.date < $1.date }

        // 相邻且同名的放假日合成一段；中秋与国庆连着放时 JSON 里是同一个名字
        var runs: [(name: String, start: CivilDate, end: CivilDate)] = []
        for entry in off {
            if let last = runs.last, last.name == entry.name, last.end.days(until: entry.date) == 1 {
                runs[runs.count - 1].end = entry.date
            } else {
                runs.append((entry.name, entry.date, entry.date))
            }
        }

        // 补班日归到「同名且日期最近」的那一段
        var makeups: [Int: [CivilDate]] = [:]
        for entry in work {
            let candidates = runs.indices.filter { runs[$0].name == entry.name }
            guard
                let owner = candidates.min(by: {
                    abs(runs[$0].start.days(until: entry.date)) < abs(runs[$1].start.days(until: entry.date))
                })
            else { continue }
            makeups[owner, default: []].append(entry.date)
        }

        var offIndex: [CivilDate: HolidayPeriod] = [:]
        var built: [HolidayPeriod] = []
        for (index, run) in runs.enumerated() {
            let period = HolidayPeriod(
                name: run.name, start: run.start, end: run.end,
                makeupWorkdays: (makeups[index] ?? []).sorted())
            built.append(period)
            for offset in 0..<period.dayCount { offIndex[period.start.adding(days: offset)] = period }
        }
        offDays = offIndex
        periods = built
        workdays = Dictionary(work.map { ($0.date, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// `date` 这一天的特殊身份；普通的周末与工作日返回 `nil`
    func status(on date: CivilDate) -> HolidayStatus? {
        if let period = offDays[date], let number = period.dayNumber(of: date) {
            return .off(period, dayNumber: number)
        }
        if let name = workdays[date] { return .makeupWorkday(name: name) }
        return nil
    }

    /// 还没结束的假期（含正在放的），最近的在前
    func upcoming(from date: CivilDate, limit: Int) -> [HolidayPeriod] {
        Array(periods.filter { $0.end >= date }.prefix(max(limit, 0)))
    }

    /// 与 `year` 年 `month` 月有交集的假期
    func periods(inYear year: Int, month: Int) -> [HolidayPeriod] {
        let first = CivilDate(year: year, month: month, day: 1)
        let last = first.adding(days: first.daysInMonth - 1)
        return periods.filter { $0.start <= last && $0.end >= first }
    }

    /// `date` 当天或之后最近的假期；`date` 已经晚于所有已知假期时为 `nil`
    func next(from date: CivilDate) -> HolidayPeriod? {
        upcoming(from: date, limit: 1).first
    }
}
