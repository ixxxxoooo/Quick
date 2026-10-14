// CalendarMonthGrid.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// 月视图的网格：格高、农历小字、周数列都由 `CalendarLayoutMetrics` 决定，随窗口尺寸变化
struct CalendarMonthGrid: View {

    let rows: [CalendarFormatting.WeekRow]
    let metrics: CalendarLayoutMetrics
    let decorations: CalendarDecorations
    @Binding var selectedDate: Date

    private var calendar: Calendar { decorations.calendar }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            weekdayHeader
            VStack(spacing: DesignTokens.Spacing.xxs) {
                ForEach(rows) { row in
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        if metrics.showsWeekNumberColumn {
                            Text(row.weekNumber.map(String.init) ?? "")
                                .font(DesignTokens.Typography.compactKeyCap)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                .frame(width: DesignTokens.Size.calendarWeekColumn)
                                .accessibilityLabel(row.weekNumber.map { "第 \($0) 周" } ?? "")
                        }
                        ForEach(row.cells) { cell in
                            dayCell(cell.date)
                        }
                    }
                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            if metrics.showsWeekNumberColumn {
                Text("周")
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(width: DesignTokens.Size.calendarWeekColumn)
            }
            ForEach(Array(CalendarFormatting.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: DesignTokens.Size.calendarWeekdayHeader)
    }

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        if let date {
            let civil = CivilDate(date, calendar: calendar)
            let almanac = decorations.almanac(for: civil)
            let status = decorations.status(on: civil)
            let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
            let isToday = calendar.isDateInToday(date)
            let hasEvents = decorations.hasEvents(on: date)
            let isHighlighted = decorations.showAlmanac && almanac.cellLabel != almanac.lunarLabel
            Button {
                selectedDate = calendar.startOfDay(for: date)
            } label: {
                VStack(spacing: 0) {
                    Text("\(civil.day)")
                        .font(DesignTokens.Typography.rowTitle)
                        .fontWeight(isToday ? .semibold : .regular)
                    // 格子太矮 / 太窄时收起农历小字，保证数字与圆点不被挤出格子
                    if metrics.showsLunar {
                        Text(decorations.showAlmanac ? almanac.cellLabel : almanac.lunarLabel)
                            .font(DesignTokens.Typography.compactKeyCap)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(subLabelColor(isSelected: isSelected, highlighted: isHighlighted))
                    }
                    Circle()
                        .fill(hasEvents ? (isSelected ? DesignTokens.Colors.onAccent : DesignTokens.Colors.progress) : .clear)
                        .frame(width: DesignTokens.Size.calendarDot, height: DesignTokens.Size.calendarDot)
                }
                .foregroundStyle(
                    isSelected
                        ? DesignTokens.Colors.onAccent
                        : (isToday ? DesignTokens.Colors.progress : DesignTokens.Colors.textPrimary)
                )
                .frame(maxWidth: .infinity)
                .frame(height: metrics.cellHeight)
                .background {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                        .fill(cellFill(isSelected: isSelected, status: status))
                }
                .overlay(alignment: .topTrailing) {
                    if let status { badge(status, isSelected: isSelected) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(for: date, almanac: almanac, status: status, hasEvents: hasEvents))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            // 空格必须是**固定高度**：`Color.clear` 在纵向上本来就是弹性的，
            // 带空格的行（首行 / 末行）会被撑到吃掉剩余高度，整个月历就变形了
            Color.clear.frame(maxWidth: .infinity).frame(height: metrics.cellHeight)
        }
    }

    private func cellFill(isSelected: Bool, status: HolidayStatus?) -> Color {
        if isSelected { return DesignTokens.Colors.progress }
        switch status {
        case .off: return DesignTokens.Colors.success.opacity(DesignTokens.Opacity.tint)
        case .makeupWorkday: return DesignTokens.Colors.warning.opacity(DesignTokens.Opacity.tint)
        case nil: return .clear
        }
    }

    private func subLabelColor(isSelected: Bool, highlighted: Bool) -> Color {
        if isSelected { return DesignTokens.Colors.onAccent }
        return highlighted ? DesignTokens.Colors.textSecondary : DesignTokens.Colors.textTertiary
    }

    private func badge(_ status: HolidayStatus, isSelected: Bool) -> some View {
        let tint: Color
        switch status {
        case .off: tint = DesignTokens.Colors.success
        case .makeupWorkday: tint = DesignTokens.Colors.warning
        }
        return Text(status.badge)
            .font(DesignTokens.Typography.calendarBadge)
            .foregroundStyle(isSelected ? DesignTokens.Colors.onAccent : tint)
            .padding(.top, DesignTokens.Spacing.xxs)
            .padding(.trailing, DesignTokens.Spacing.xs)
    }

    private func accessibilityLabel(
        for date: Date, almanac: AlmanacDay, status: HolidayStatus?, hasEvents: Bool
    ) -> String {
        var text = date.formatted(.dateTime.month().day().weekday(.wide)) + "，农历" + almanac.lunarText
        if !almanac.highlights.isEmpty { text += "，" + almanac.highlights.joined(separator: "、") }
        if let status { text += "，" + status.detailText }
        return text + (hasEvents ? "，有日程" : "")
    }
}
