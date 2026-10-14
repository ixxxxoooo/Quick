// CalendarWeekView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// 周视图：一天一栏，每栏列出当日日程、休 / 班角标与农历
///
/// 宽度够就七列并排；不够（窄窗口）改成纵向「一天一段」，不做横向滚动。
struct CalendarWeekView: View {

    let days: [Date]
    let eventsByDay: [Date: [CalendarEvent]]
    let isVertical: Bool
    let decorations: CalendarDecorations
    @Binding var selectedDate: Date

    private var calendar: Calendar { decorations.calendar }

    var body: some View {
        ScrollView {
            if isVertical {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(days, id: \.self) { day in
                        dayColumn(day, fillsHeight: false)
                    }
                }
                .padding(DesignTokens.Spacing.xl)
            } else {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                    ForEach(days, id: \.self) { day in
                        dayColumn(day, fillsHeight: true)
                            .frame(minWidth: DesignTokens.Size.calendarWeekDayMinWidth)
                    }
                }
                .padding(DesignTokens.Spacing.xl)
            }
        }
    }

    private func dayColumn(_ day: Date, fillsHeight: Bool) -> some View {
        let civil = CivilDate(day, calendar: calendar)
        let almanac = decorations.almanac(for: civil)
        let status = decorations.status(on: civil)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let events = eventsByDay[calendar.startOfDay(for: day)] ?? []

        return Button {
            selectedDate = calendar.startOfDay(for: day)
        } label: {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                header(day: day, civil: civil, almanac: almanac, status: status, isToday: isToday, isSelected: isSelected)
                if events.isEmpty {
                    Text("无日程")
                        .font(DesignTokens.Typography.compactKeyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                } else {
                    ForEach(events) { event in
                        eventChip(event)
                    }
                }
                if fillsHeight { Spacer(minLength: 0) }
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .background(
                isSelected ? DesignTokens.Colors.selection : DesignTokens.Colors.cardFill,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .strokeBorder(
                        isToday ? DesignTokens.Colors.progress : DesignTokens.Colors.cardStroke,
                        lineWidth: DesignTokens.Size.hairline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func header(
        day: Date, civil: CivilDate, almanac: AlmanacDay, status: HolidayStatus?,
        isToday: Bool, isSelected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer(minLength: 0)
                if let status {
                    Text(status.badge)
                        .font(DesignTokens.Typography.calendarBadge)
                        .foregroundStyle(
                            status.isOffDay ? DesignTokens.Colors.success : DesignTokens.Colors.warning)
                }
            }
            Text("\(civil.day)")
                .font(DesignTokens.Typography.panelTitle)
                .foregroundStyle(isToday ? DesignTokens.Colors.progress : DesignTokens.Colors.textPrimary)
            Text(decorations.showAlmanac ? almanac.cellLabel : almanac.lunarLabel)
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .lineLimit(1)
        }
    }

    private func eventChip(_ event: CalendarEvent) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(event.displayColor)
                .frame(width: DesignTokens.Size.calendarDot, height: DesignTokens.Size.calendarDot)
                .padding(.top, DesignTokens.Spacing.xs)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                Text(event.timeRange)
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
    }
}

extension HolidayStatus {
    /// 是否为放假日（休），否则是补班
    var isOffDay: Bool {
        if case .off = self { return true }
        return false
    }
}
