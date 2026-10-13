// CalendarView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 日历插件视图
///
/// 左：月历（休 / 班角标、节日与节气小字、事件小圆点、可选周数列）+ 假期倒数；
/// 右：所选日期的信息卡、日程、近期节假日。
/// 未授权日历时月历、农历与节假日仍可用，日程区给出授权入口 —— 授权由用户主动触发，不在启动时弹框。
struct CalendarView: View {

    let service: CalendarService
    let holidayStore: HolidayStore

    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var events: [CalendarEvent] = []
    @State private var markedDays: Set<Date> = []
    @State private var holidays: HolidayCalendar
    @State private var observances: [Almanac.Observance] = []

    @AppStorage(PluginSettingKey.Calendar.showWeekNumber) private var showWeekNumber = false
    @AppStorage(PluginSettingKey.Calendar.autoExtractMeetingLinks) private var extractsLinks = true
    @AppStorage(PluginSettingKey.Calendar.showHolidays) private var showHolidays = true
    @AppStorage(PluginSettingKey.Calendar.showAlmanac) private var showAlmanac = true

    private let calendar = Calendar.current

    init(service: CalendarService, holidayStore: HolidayStore) {
        self.service = service
        self.holidayStore = holidayStore
        _holidays = State(initialValue: holidayStore.calendar)
    }

    var body: some View {
        HStack(spacing: 0) {
            monthPanel
                .frame(width: DesignTokens.Size.calendarPanelWidth)

            Divider().opacity(DesignTokens.Opacity.divider)

            dayPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { service.refreshAccessState() }
        .task(id: selectedDate) { reloadEvents() }
        .task(id: displayedMonth) { reloadMarks() }
        .task { await refreshHolidays() }
        .task { observances = Almanac.upcomingObservances(from: today, limit: 3) }
        .onChange(of: service.accessState) { _, _ in
            reloadEvents()
            reloadMarks()
        }
        .onChange(of: extractsLinks) { _, _ in reloadEvents() }
    }

    private func reloadEvents() {
        events = service.events(on: selectedDate)
    }

    private func reloadMarks() {
        markedDays = service.daysWithEvents(inMonthOf: displayedMonth)
    }

    /// 到点才联网；拿到新数据后换掉内存里的那份，月历立刻带上新年份的休 / 班
    private func refreshHolidays() async {
        guard CalendarPreferences.updatesHolidaysOnline() else { return }
        if await holidayStore.refreshIfNeeded() { holidays = holidayStore.calendar }
    }

    private var today: CivilDate { CivilDate(Date(), calendar: calendar) }

    // MARK: - 月历

    private var monthPanel: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(DesignTokens.Typography.panelTitle)
                Spacer()
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("上个月")
                Button("今天") { goToToday() }
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("下个月")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            weekdayHeader

            let rows = CalendarFormatting.monthGrid(containing: displayedMonth, calendar: calendar)
            VStack(spacing: DesignTokens.Spacing.xxs) {
                ForEach(rows) { row in
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        if showWeekNumber {
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

            if showHolidays { monthSummary }
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.xl)
    }

    @ViewBuilder
    private var monthSummary: some View {
        let month = CivilDate(displayedMonth, calendar: calendar)
        let monthPeriods = holidays.periods(inYear: month.year, month: month.month)
        let next = holidays.next(from: today)
        if next != nil || !monthPeriods.isEmpty {
            MonthHolidaySummary(next: next, monthPeriods: Array(monthPeriods.prefix(3)), today: today)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            if showWeekNumber {
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
    }

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        if let date {
            let civil = CivilDate(date, calendar: calendar)
            let almanac = Almanac.day(for: civil)
            let status = showHolidays ? holidays.status(on: civil) : nil
            let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
            let isToday = calendar.isDateInToday(date)
            let hasEvents = markedDays.contains(calendar.startOfDay(for: date))
            let isHighlighted = showAlmanac && almanac.cellLabel != almanac.lunarLabel
            Button {
                selectedDate = calendar.startOfDay(for: date)
            } label: {
                VStack(spacing: 0) {
                    Text("\(civil.day)")
                        .font(DesignTokens.Typography.rowTitle)
                        .fontWeight(isToday ? .semibold : .regular)
                    Text(showAlmanac ? almanac.cellLabel : almanac.lunarLabel)
                        .font(DesignTokens.Typography.compactKeyCap)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(subLabelColor(isSelected: isSelected, highlighted: isHighlighted))
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
                .frame(height: DesignTokens.Size.calendarCellHeight)
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
            Color.clear.frame(maxWidth: .infinity).frame(height: DesignTokens.Size.calendarCellHeight)
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

    private func shiftMonth(_ delta: Int) {
        guard let moved = calendar.date(byAdding: .month, value: delta, to: displayedMonth),
            let start = calendar.dateInterval(of: .month, for: moved)?.start
        else { return }
        displayedMonth = start
    }

    private func goToToday() {
        let today = calendar.startOfDay(for: Date())
        selectedDate = today
        displayedMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
    }

    // MARK: - 所选日期

    private var dayPanel: some View {
        let civil = CivilDate(selectedDate, calendar: calendar)
        return ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                DayInfoCard(
                    date: selectedDate,
                    day: Almanac.day(for: civil),
                    status: showHolidays ? holidays.status(on: civil) : nil,
                    weekNumber: showWeekNumber
                        ? CalendarFormatting.weekNumber(for: selectedDate, calendar: calendar) : nil,
                    showAlmanac: showAlmanac)

                CalendarEventsView(service: service, events: events, isToday: calendar.isDateInToday(selectedDate))

                if showHolidays {
                    UpcomingHolidaysCard(periods: holidays.upcoming(from: today, limit: 3), today: today)
                }
                if showAlmanac && !observances.isEmpty {
                    UpcomingObservancesCard(observances: observances, today: today)
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
    }
}
