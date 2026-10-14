// CalendarEventStyle.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

extension CalendarEvent {

    /// 事件的显示色：用所属日历自带的颜色，取不到时用主题强调色
    var displayColor: Color {
        guard let c = color else { return DesignTokens.Colors.progress }
        return Color(red: c.red, green: c.green, blue: c.blue)  // ui-literal-ok: 日历自带的用户颜色，不是设计值
    }
}

extension CalendarLayoutMetrics.Limits {

    /// 视图层的真实数值：全部来自 `DesignTokens`，Model 只认这个值对象
    static var design: CalendarLayoutMetrics.Limits {
        CalendarLayoutMetrics.Limits(
            compactBelowWidth: DesignTokens.Size.calendarCompactWidth,
            monthColumnFraction: monthColumnFraction,
            monthColumnMin: DesignTokens.Size.calendarMonthColumnMin,
            monthColumnMax: DesignTokens.Size.calendarMonthColumnMax,
            cellMinHeight: DesignTokens.Size.calendarCellMinHeight,
            cellMaxHeight: DesignTokens.Size.calendarCellMaxHeight,
            lunarMinCellHeight: DesignTokens.Size.calendarLunarMinCellHeight,
            lunarMinCellWidth: DesignTokens.Size.calendarLunarMinCellWidth,
            weekNumberMinCellWidth: DesignTokens.Size.calendarWeekNumberMinCell,
            gridChromeHeight: DesignTokens.Spacing.xl * 2 + DesignTokens.Size.calendarWeekdayHeader
                + DesignTokens.Spacing.md,
            summaryHeight: DesignTokens.Size.calendarSummaryHeight,
            summaryMinCellHeight: DesignTokens.Size.calendarSummaryMinCell,
            rowSpacing: DesignTokens.Spacing.xxs,
            horizontalPadding: DesignTokens.Spacing.xl,
            weekNumberColumn: DesignTokens.Size.calendarWeekColumn,
            weekColumnsMinWidth: DesignTokens.Size.calendarWeekColumnsMinWidth)
    }

    /// 双栏时月历占内容宽度的比例（比例不是设计尺寸，不进令牌）
    private static let monthColumnFraction: CGFloat = 0.42
}
