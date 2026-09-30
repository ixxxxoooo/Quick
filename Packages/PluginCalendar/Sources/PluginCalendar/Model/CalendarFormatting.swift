// CalendarFormatting.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 法定节假日调休标记
enum CalendarWorkdayMark: String, Sendable, Equatable {
    /// 法定放假（「休」）
    case holiday = "休"
    /// 调休补班（「班」）
    case workday = "班"
}

/// 月历网格中的单日模型
struct CalendarDayCell: Identifiable, Sendable, Equatable {
    /// 当天零点时间戳作为稳定主键
    var id: TimeInterval { date.timeIntervalSince1970 }
    /// 当天起始时刻（00:00）
    let date: Date
    /// 公历年
    let year: Int
    /// 公历月（1...12）
    let month: Int
    /// 公历日（1...31）
    let day: Int
    /// 是否属于当前展示的月份
    let isCurrentMonth: Bool
    /// 是否是今天
    let isToday: Bool
    /// 是否是周末（周六、周日）
    let isWeekend: Bool
    /// 干支生肖纪年（如「丙午马年」）
    let cyclicalYearText: String
    /// 农历月名称（如「八月」「闰六月」）
    let lunarMonthText: String
    /// 农历日名称（如「初一」「二十」）
    let lunarDayText: String
    /// 二十四节气（若当天是节气）
    let solarTerm: String?
    /// 当天命中的传统/公历节日列表（传统节日优先）
    let festivals: [String]
    /// 法定节假日放假/补班标记
    let workdayMark: CalendarWorkdayMark?

    /// 单元格底部展示的短标签（优先级：节日 > 二十四节气 > 初一显示农历月 > 农历日）
    var subtitle: String {
        if let firstFestival = festivals.first {
            return firstFestival
        }
        if let solarTerm {
            return solarTerm
        }
        if lunarDayText == "初一" {
            return lunarMonthText
        }
        return lunarDayText
    }

    /// 单元格副标签是否高亮（节日或节气时高亮）
    var isSubtitleHighlighted: Bool {
        !festivals.isEmpty || solarTerm != nil
    }

    /// 完整农历文案（如「丙午马年 八月二十」）
    var fullLunarDescription: String {
        "\(cyclicalYearText) \(lunarMonthText)\(lunarDayText)"
    }
}

/// 月历网格中的一行（一周 7 天）
struct CalendarWeekRow: Identifiable, Sendable, Equatable {
    /// 行索引（0..<6）
    let index: Int
    /// 当周属于当年的第几周
    let weekOfYear: Int
    /// 周一至周日的 7 个单元格
    let days: [CalendarDayCell]

    var id: Int { index }
}

/// 日历相关文本格式化与历法计算（纯 Foundation，无 UI 依赖）
enum CalendarFormatting {

    // MARK: - 基础常量表

    private static let heavenlyStems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let earthlyBranches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    private static let zodiacAnimals = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]

    private static let lunarMonths = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]

    private static let lunarDays = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    /// 周一到周日的表头标题
    static let weekdayHeaders = ["一", "二", "三", "四", "五", "六", "日"]

    /// 二十四节气名称（按公历 1 月至 12 月顺序，每月两个节气）
    private static let solarTermNames = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分",
        "清明", "谷雨", "立夏", "小满", "芒种", "夏至",
        "小暑", "大暑", "立秋", "处暑", "白露", "秋分",
        "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
    ]

    /// 21 世纪（2000–2099）24 节气定气常数 C 表（与 `solarTermNames` 一一对应）
    private static let solarTermC21st: [Double] = [
        5.4055, 20.12, 3.87, 18.73, 5.63, 20.646,
        4.81, 20.1, 5.52, 21.04, 5.678, 21.37,
        7.108, 22.83, 7.5, 23.13, 7.646, 23.042,
        8.318, 23.438, 7.438, 22.36, 7.18, 21.94
    ]

    // MARK: - 公开格式化接口

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

    /// 构造以周一为首日的公历日历
    static func mondayFirstGregorianCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2  // 周一
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// 生成指定月份的 6 行 × 7 列（42 天）月历网格
    static func monthGrid(
        for monthDate: Date,
        today: Date = Date(),
        timeZone: TimeZone = .current
    ) -> [CalendarWeekRow] {
        let gregorian = mondayFirstGregorianCalendar(timeZone: timeZone)
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = timeZone

        let monthComponents = gregorian.dateComponents([.year, .month], from: monthDate)
        guard let firstOfMonth = gregorian.date(from: monthComponents) else { return [] }

        // 计算当月 1 号距离本周一偏移了多少天（周一 -> 0，周二 -> 1，…，周日 -> 6）
        let weekday = gregorian.component(.weekday, from: firstOfMonth)
        let leadingOffset = (weekday + 5) % 7
        guard let gridStart = gregorian.date(byAdding: .day, value: -leadingOffset, to: firstOfMonth) else {
            return []
        }

        let targetMonth = monthComponents.month ?? 1
        let targetYear = monthComponents.year ?? 2026

        var rows: [CalendarWeekRow] = []
        rows.reserveCapacity(6)

        for weekIndex in 0..<6 {
            var days: [CalendarDayCell] = []
            days.reserveCapacity(7)

            for dayOffset in 0..<7 {
                let offset = weekIndex * 7 + dayOffset
                guard let currentDate = gregorian.date(byAdding: .day, value: offset, to: gridStart) else {
                    continue
                }
                let cell = buildDayCell(
                    for: currentDate,
                    targetYear: targetYear,
                    targetMonth: targetMonth,
                    today: today,
                    gregorian: gregorian,
                    chinese: chinese
                )
                days.append(cell)
            }

            if let firstDay = days.first {
                let weekOfYear = gregorian.component(.weekOfYear, from: firstDay.date)
                rows.append(CalendarWeekRow(index: weekIndex, weekOfYear: weekOfYear, days: days))
            }
        }

        return rows
    }

    /// 构造单日的完整日历信息
    static func dayCell(
        for date: Date,
        referenceMonth: Date? = nil,
        today: Date = Date(),
        timeZone: TimeZone = .current
    ) -> CalendarDayCell {
        let gregorian = mondayFirstGregorianCalendar(timeZone: timeZone)
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = timeZone

        let ref = referenceMonth ?? date
        let refComps = gregorian.dateComponents([.year, .month], from: ref)
        return buildDayCell(
            for: date,
            targetYear: refComps.year ?? 2026,
            targetMonth: refComps.month ?? 1,
            today: today,
            gregorian: gregorian,
            chinese: chinese
        )
    }

    /// 计算选中日期相对于今天的简短说明（如「今天」「明天」「昨天」「3 天后」「2 天前」）
    static func relativeDayDescription(
        for date: Date,
        today: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let gregorian = mondayFirstGregorianCalendar(timeZone: timeZone)
        let startTarget = gregorian.startOfDay(for: date)
        let startToday = gregorian.startOfDay(for: today)
        let diff = gregorian.dateComponents([.day], from: startToday, to: startTarget).day ?? 0
        switch diff {
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        case -1: return "昨天"
        case -2: return "前天"
        default:
            return diff > 0 ? "\(diff) 天后" : "\(-diff) 天前"
        }
    }

    /// 格式化公历年月标题（如「2026年 9月」）
    static func monthTitle(for date: Date, timeZone: TimeZone = .current) -> String {
        let gregorian = mondayFirstGregorianCalendar(timeZone: timeZone)
        let comps = gregorian.dateComponents([.year, .month], from: date)
        return "\(comps.year ?? 2026)年 \(comps.month ?? 1)月"
    }

    /// 格式化星期名称（如「星期三」）
    static func weekdayTitle(for date: Date, timeZone: TimeZone = .current) -> String {
        let gregorian = mondayFirstGregorianCalendar(timeZone: timeZone)
        let weekday = gregorian.component(.weekday, from: date)
        let names = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        guard weekday >= 1, weekday <= 7 else { return "" }
        return names[weekday - 1]
    }

    // MARK: - 内部历法与节气/节日计算

    private static func buildDayCell(
        for date: Date,
        targetYear: Int,
        targetMonth: Int,
        today: Date,
        gregorian: Calendar,
        chinese: Calendar
    ) -> CalendarDayCell {
        let dayStart = gregorian.startOfDay(for: date)
        let gComps = gregorian.dateComponents([.year, .month, .day, .weekday], from: dayStart)
        let year = gComps.year ?? targetYear
        let month = gComps.month ?? targetMonth
        let day = gComps.day ?? 1
        let weekday = gComps.weekday ?? 2

        let isCurrentMonth = (year == targetYear && month == targetMonth)
        let isToday = gregorian.isDate(dayStart, inSameDayAs: today)
        let isWeekend = (weekday == 1 || weekday == 7)

        // 农历组件
        let lComps = chinese.dateComponents([.year, .month, .day, .isLeapMonth], from: dayStart)
        let cyclicalYear = max(1, min(60, lComps.year ?? 1))
        let lMonth = max(1, min(12, lComps.month ?? 1))
        let lDay = max(1, min(30, lComps.day ?? 1))
        let isLeapMonth = lComps.isLeapMonth ?? false

        let stem = heavenlyStems[(cyclicalYear - 1) % 10]
        let branch = earthlyBranches[(cyclicalYear - 1) % 12]
        let zodiac = zodiacAnimals[(cyclicalYear - 1) % 12]
        let cyclicalYearText = "\(stem)\(branch)\(zodiac)年"

        let baseMonthName = lunarMonths[lMonth - 1]
        let lunarMonthText = isLeapMonth ? "闰\(baseMonthName)" : baseMonthName
        let lunarDayText = lunarDays[lDay - 1]

        // 二十四节气
        let term = solarTerm(year: year, month: month, day: day)

        // 传统与公历节日
        let dayFestivals = festivals(
            date: dayStart,
            year: year,
            month: month,
            day: day,
            weekday: weekday,
            lunarMonth: lMonth,
            lunarDay: lDay,
            isLeapMonth: isLeapMonth,
            solarTerm: term,
            gregorian: gregorian,
            chinese: chinese
        )

        let mark = workdayMark(year: year, month: month, day: day)

        return CalendarDayCell(
            date: dayStart,
            year: year,
            month: month,
            day: day,
            isCurrentMonth: isCurrentMonth,
            isToday: isToday,
            isWeekend: isWeekend,
            cyclicalYearText: cyclicalYearText,
            lunarMonthText: lunarMonthText,
            lunarDayText: lunarDayText,
            solarTerm: term,
            festivals: dayFestivals,
            workdayMark: mark
        )
    }

    /// 计算公历某年某月某日对应的二十四节气（2000–2099 年）
    static func solarTerm(year: Int, month: Int, day: Int) -> String? {
        guard year >= 2000, year <= 2099, month >= 1, month <= 12 else { return nil }
        let y = year % 100
        let leapCount = (month <= 2) ? ((y - 1) / 4) : (y / 4)

        for slot in 0...1 {
            let index = (month - 1) * 2 + slot
            let c = solarTermC21st[index]
            var expectedDay = Int(Double(y) * 0.2422 + c) - leapCount
            expectedDay += solarTermDelta(year: year, termIndex: index)
            if day == expectedDay {
                return solarTermNames[index]
            }
        }
        return nil
    }

    /// 21 世纪个别年份节气 ±1 日修正表
    private static func solarTermDelta(year: Int, termIndex: Int) -> Int {
        switch (year, termIndex) {
        case (2019, 0): return -1   // 小寒
        case (2082, 0): return 1
        case (2000, 1): return 1    // 大寒
        case (2026, 3): return -1   // 雨水
        case (2084, 5): return 1    // 春分
        case (2008, 9): return 1    // 小满
        case (2002, 10): return 1   // 芒种
        case (2016, 12): return 1   // 小暑
        case (2022, 14): return 1   // 立秋
        case (2027, 16): return 1   // 白露
        case (2042, 17): return 1   // 秋分
        case (2089, 19): return 1   // 霜降
        case (2089, 20): return 1   // 立冬
        case (2021, 23): return -1  // 冬至
        default: return 0
        }
    }

    /// 计算当天命中的中国传统节日与常用公历节日
    private static func festivals(
        date: Date,
        year: Int,
        month: Int,
        day: Int,
        weekday: Int,
        lunarMonth: Int,
        lunarDay: Int,
        isLeapMonth: Bool,
        solarTerm: String?,
        gregorian: Calendar,
        chinese: Calendar
    ) -> [String] {
        var result: [String] = []

        // 1. 中国农历传统节日（闰月不计入传统正节）
        if !isLeapMonth {
            switch (lunarMonth, lunarDay) {
            case (1, 1): result.append("春节")
            case (1, 15): result.append("元宵节")
            case (2, 2): result.append("龙抬头")
            case (5, 5): result.append("端午节")
            case (7, 7): result.append("七夕")
            case (7, 15): result.append("中元节")
            case (8, 15): result.append("中秋节")
            case (9, 9): result.append("重阳节")
            case (12, 8): result.append("腊八节")
            case (12, 23): result.append("小年")
            default: break
            }

            // 除夕：腊月的最后一天（明天是农历正月初一）
            if lunarMonth == 12, (lunarDay == 29 || lunarDay == 30),
                let tomorrow = gregorian.date(byAdding: .day, value: 1, to: date)
            {
                let tomorrowComps = chinese.dateComponents([.month, .day, .isLeapMonth], from: tomorrow)
                if tomorrowComps.month == 1, tomorrowComps.day == 1, tomorrowComps.isLeapMonth != true {
                    result.append("除夕")
                }
            }
        }

        // 2. 清明既是节气也是法定传统节日
        if solarTerm == "清明" {
            result.append("清明节")
        }

        // 3. 公历固定节日
        switch (month, day) {
        case (1, 1): result.append("元旦")
        case (2, 14): result.append("情人节")
        case (3, 8): result.append("妇女节")
        case (3, 12): result.append("植树节")
        case (4, 1): result.append("愚人节")
        case (5, 1): result.append("劳动节")
        case (5, 4): result.append("青年节")
        case (6, 1): result.append("儿童节")
        case (7, 1): result.append("建党节")
        case (8, 1): result.append("建军节")
        case (9, 10): result.append("教师节")
        case (10, 1): result.append("国庆节")
        case (12, 24): result.append("平安夜")
        case (12, 25): result.append("圣诞节")
        default: break
        }

        // 4. 母亲节（5 月第 2 个周日）与父亲节（6 月第 3 个周日）
        if month == 5, weekday == 1, (8...14).contains(day) {
            result.append("母亲节")
        } else if month == 6, weekday == 1, (15...21).contains(day) {
            result.append("父亲节")
        }

        return result
    }

    // MARK: - 法定节假日与调休补班表（2025–2026）

    /// 查询某天是否为法定节假日放假（休）或调休上班（班）
    static func workdayMark(year: Int, month: Int, day: Int) -> CalendarWorkdayMark? {
        let key = year * 10000 + month * 100 + day
        if statutoryHolidays.contains(key) {
            return .holiday
        }
        if makeupWorkdays.contains(key) {
            return .workday
        }
        return nil
    }

    /// 国务院法定节假日放假日期（YYYYMMDD）
    private static let statutoryHolidays: Set<Int> = [
        // 2025 年
        20250101,
        20250128, 20250129, 20250130, 20250131, 20250201, 20250202, 20250203, 20250204,
        20250404, 20250405, 20250406,
        20250501, 20250502, 20250503, 20250504, 20250505,
        20250531, 20250601, 20250602,
        20251001, 20251002, 20251003, 20251004, 20251005, 20251006, 20251007, 20251008,
        // 2026 年
        20260101, 20260102, 20260103,
        20260215, 20260216, 20260217, 20260218, 20260219, 20260220, 20260221, 20260222, 20260223,
        20260404, 20260405, 20260406,
        20260501, 20260502, 20260503, 20260504, 20260505,
        20260619, 20260620, 20260621,
        20260925, 20260926, 20260927,
        20261001, 20261002, 20261003, 20261004, 20261005, 20261006, 20261007
    ]

    /// 国务院法定节假日调休补班日期（YYYYMMDD）
    private static let makeupWorkdays: Set<Int> = [
        // 2025 年
        20250126, 20250208, 20250427, 20250928, 20251011,
        // 2026 年
        20260104, 20260214, 20260228, 20260509, 20260920, 20261010
    ]
}
