// CalendarViewMode.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 日历的三种视图：月 / 周 / 日
///
/// 三个视图共用同一份状态（所选日期 + 月历显示的月份），切换视图不丢位置。
/// 选中的视图持久化在 `calendar.viewMode`，存储值非法时回落到月视图。
enum CalendarViewMode: String, CaseIterable, Identifiable, Sendable {
    case month
    case week
    case day

    var id: String { rawValue }

    /// 分段控件上的文字
    var title: String {
        switch self {
        case .month: "月"
        case .week: "周"
        case .day: "日"
        }
    }

    /// 上一个 / 下一个按钮的无障碍文字
    func stepLabel(forward: Bool) -> String {
        switch self {
        case .month: forward ? "下个月" : "上个月"
        case .week: forward ? "下一周" : "上一周"
        case .day: forward ? "后一天" : "前一天"
        }
    }

    static let `default` = CalendarViewMode.month

    /// 从存储值还原；缺失或非法回落默认
    init(storedValue: String?) {
        self = storedValue.flatMap(CalendarViewMode.init(rawValue:)) ?? .default
    }
}

/// 视图内「上一个 / 下一个 / 今天」的位置计算
///
/// 纯函数：输入当前所选日期与视图，输出新的所选日期与月历应显示的月份。
/// 三个视图都把选中日期一起挪走，保证切换视图时所选日期始终落在可见范围里。
enum CalendarNavigation {

    struct Position: Equatable, Sendable {
        /// 所选日期（当天零点）
        let selectedDate: Date
        /// 月历显示的月份（当月第一天零点）
        let displayedMonth: Date
    }

    /// 前后移动一步
    /// - Parameters:
    ///   - selected: 当前所选日期
    ///   - mode: 当前视图
    ///   - delta: -1 上一个，+1 下一个
    static func moved(
        from selected: Date, mode: CalendarViewMode, by delta: Int, calendar: Calendar = .current
    ) -> Position {
        let start = calendar.startOfDay(for: selected)
        let component: Calendar.Component
        let value: Int
        switch mode {
        case .month: (component, value) = (.month, delta)
        case .week: (component, value) = (.weekOfYear, delta)
        case .day: (component, value) = (.day, delta)
        }
        // 按月移动时 `date(byAdding:.month)` 会把 31 号夹到短月的最后一天，正好是想要的行为
        let target = calendar.date(byAdding: component, value: value, to: start) ?? start
        return position(for: target, calendar: calendar)
    }

    /// 回到某一天（今天）
    static func position(for date: Date, calendar: Calendar = .current) -> Position {
        let day = calendar.startOfDay(for: date)
        let month = calendar.dateInterval(of: .month, for: day)?.start ?? day
        return Position(selectedDate: day, displayedMonth: month)
    }
}
