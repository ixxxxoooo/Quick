// CalendarView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 日历插件视图
///
/// 顶部是工具栏（标题 · 月/周/日 · 上一个/今天/下一个），下面按所选视图展示：
/// - 月：月历网格 + 所选日期详情；
/// - 周：一天一栏，每栏列出当日日程；
/// - 日：当天时间轴 + 日期信息卡。
///
/// **内容区跟着窗口尺寸走**（`CalendarLayoutMetrics`）：拖大格子变高、拖窄收成单栏、
/// 过矮自动收起农历小字与假期摘要，永远不裁剪。三个视图共用 `selectedDate` / `displayedMonth`，
/// 切换视图不丢位置。未授权日历时月历、农历与节假日仍可用，日程区给出授权入口 ——
/// 授权由用户主动触发，不在启动时弹框。
struct CalendarView: View {

    let service: CalendarService
    let holidayStore: HolidayStore

    @State private var displayedMonth: Date
    @State private var selectedDate: Date
    @State private var gridRows: [CalendarFormatting.WeekRow]
    @State private var events: [CalendarEvent] = []
    @State private var weekEvents: [Date: [CalendarEvent]] = [:]
    @State private var markedDays: Set<Date> = []
    @State private var holidays: HolidayCalendar
    @State private var observances: [Almanac.Observance] = []

    @AppStorage(PluginSettingKey.Calendar.viewMode) private var modeRaw = CalendarViewMode.default.rawValue
    @AppStorage(PluginSettingKey.Calendar.showWeekNumber) private var showWeekNumber = false
    @AppStorage(PluginSettingKey.Calendar.autoExtractMeetingLinks) private var extractsLinks = true
    @AppStorage(PluginSettingKey.Calendar.showHolidays) private var showHolidays = true
    @AppStorage(PluginSettingKey.Calendar.showAlmanac) private var showAlmanac = true

    private let calendar = Calendar.current

    init(service: CalendarService, holidayStore: HolidayStore) {
        self.service = service
        self.holidayStore = holidayStore
        let position = CalendarNavigation.position(for: Date())
        _displayedMonth = State(initialValue: position.displayedMonth)
        _selectedDate = State(initialValue: position.selectedDate)
        _gridRows = State(initialValue: CalendarFormatting.monthGrid(containing: position.displayedMonth))
        _holidays = State(initialValue: holidayStore.calendar)
    }

    private var mode: CalendarViewMode { CalendarViewMode(storedValue: modeRaw) }

    private var weekDays: [Date] { CalendarFormatting.weekDates(containing: selectedDate, calendar: calendar) }

    private var today: CivilDate { CivilDate(Date(), calendar: calendar) }

    private var decorations: CalendarDecorations {
        CalendarDecorations(
            holidays: holidays, showHolidays: showHolidays, showAlmanac: showAlmanac,
            markedDays: markedDays, calendar: calendar)
    }

    /// 周事件的加载键：只有周视图才需要，且随「哪一周 / 授权状态」变化
    private struct WeekLoadKey: Hashable {
        let weekStart: Date?
        let authorized: Bool
    }

    private var weekLoadKey: WeekLoadKey {
        WeekLoadKey(
            weekStart: mode == .week ? weekDays.first : nil,
            authorized: service.accessState == .authorized)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(DesignTokens.Opacity.divider)
            GeometryReader { proxy in
                content(size: proxy.size)
            }
        }
        .onAppear { service.refreshAccessState() }
        .task(id: selectedDate) { reloadEvents() }
        .task(id: displayedMonth) { reloadMarks() }
        .task(id: weekLoadKey) { reloadWeekEvents() }
        .task { await refreshHolidays() }
        .task { observances = Almanac.upcomingObservances(from: today, limit: 3) }
        .onChange(of: displayedMonth) { _, month in
            gridRows = CalendarFormatting.monthGrid(containing: month, calendar: calendar)
        }
        .onChange(of: selectedDate) { _, date in
            // 周 / 日视图里挪走了所选日期：月历显示的月份要跟上，切回月视图时才不会对不上
            if !calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
            }
        }
        .onChange(of: service.accessState) { _, _ in
            reloadEvents()
            reloadMarks()
            reloadWeekEvents()
        }
        .onChange(of: extractsLinks) { _, _ in
            reloadEvents()
            reloadWeekEvents()
        }
    }

    // MARK: - 数据

    private func reloadEvents() {
        events = service.events(on: selectedDate)
    }

    private func reloadMarks() {
        markedDays = service.daysWithEvents(inMonthOf: displayedMonth)
    }

    /// 周视图一次取一周，再按天归并；不逐日各查一次
    private func reloadWeekEvents() {
        guard mode == .week, let first = weekDays.first,
            let last = weekDays.last,
            let end = calendar.date(byAdding: .day, value: 1, to: last)
        else { return }
        weekEvents = CalendarDayLayout.eventsByDay(
            service.events(from: first, to: end), days: weekDays, calendar: calendar)
    }

    /// 到点才联网；拿到新数据后换掉内存里的那份，月历立刻带上新年份的休 / 班
    private func refreshHolidays() async {
        guard CalendarPreferences.updatesHolidaysOnline() else { return }
        if await holidayStore.refreshIfNeeded() { holidays = holidayStore.calendar }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text(title)
                .font(DesignTokens.Typography.panelTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: DesignTokens.Spacing.md)

            Picker("视图", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
                ForEach(CalendarViewMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: DesignTokens.Size.calendarModePicker)

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(mode.stepLabel(forward: false))
                Button("今天") { goToToday() }
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel(mode.stepLabel(forward: true))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private var title: String {
        switch mode {
        case .month:
            return displayedMonth.formatted(.dateTime.year().month(.wide))
        case .week:
            guard let first = weekDays.first, let last = weekDays.last else { return "" }
            return first.formatted(.dateTime.year().month().day()) + " – "
                + last.formatted(.dateTime.month().day())
        case .day:
            return selectedDate.formatted(.dateTime.year().month().day().weekday(.wide))
        }
    }

    private func step(_ delta: Int) {
        apply(CalendarNavigation.moved(from: selectedDate, mode: mode, by: delta, calendar: calendar))
    }

    private func goToToday() {
        apply(CalendarNavigation.position(for: Date(), calendar: calendar))
    }

    private func apply(_ position: CalendarNavigation.Position) {
        selectedDate = position.selectedDate
        displayedMonth = position.displayedMonth
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        switch mode {
        case .month: monthContent(size: size)
        case .week: weekContent(size: size)
        case .day: dayContent(size: size)
        }
    }

    // MARK: 月

    private func monthContent(size: CGSize) -> some View {
        let metrics = CalendarLayoutMetrics.make(
            size: size, rows: gridRows.count, wantsWeekNumber: showWeekNumber,
            wantsSummary: showHolidays, limits: .design)

        return Group {
            switch metrics.columns {
            case .double:
                HStack(spacing: 0) {
                    monthPanel(metrics)
                        .frame(width: metrics.monthColumnWidth)
                    Divider().opacity(DesignTokens.Opacity.divider)
                    ScrollView { dayDetail }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .single:
                ScrollView {
                    VStack(spacing: 0) {
                        monthPanel(metrics)
                        Divider().opacity(DesignTokens.Opacity.divider)
                        dayDetail
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func monthPanel(_ metrics: CalendarLayoutMetrics) -> some View {
        let panel = VStack(spacing: DesignTokens.Spacing.md) {
            CalendarMonthGrid(
                rows: gridRows, metrics: metrics, decorations: decorations, selectedDate: $selectedDate)
            if metrics.showsSummary { monthSummary }
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.xl)

        // 双栏下连最小格高都放不下时月历栏自己滚动，而不是把底行裁掉
        if metrics.scrollsMonth { ScrollView { panel } } else { panel }
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

    // MARK: 周

    private func weekContent(size: CGSize) -> some View {
        let metrics = CalendarLayoutMetrics.make(
            size: size, rows: gridRows.count, wantsWeekNumber: false, wantsSummary: false,
            limits: .design)

        return VStack(spacing: 0) {
            permissionStrip
            CalendarWeekView(
                days: weekDays, eventsByDay: weekEvents, isVertical: metrics.weekIsVertical,
                decorations: decorations, selectedDate: $selectedDate)
        }
    }

    // MARK: 日

    private func dayContent(size: CGSize) -> some View {
        let metrics = CalendarLayoutMetrics.make(
            size: size, rows: gridRows.count, wantsWeekNumber: false, wantsSummary: false,
            limits: .design)
        let timeline = CalendarDayLayout.timeline(events: events, on: selectedDate, calendar: calendar)
        let isToday = calendar.isDateInToday(selectedDate)

        return Group {
            switch metrics.columns {
            case .double:
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        permissionStrip
                        CalendarDayTimeline(day: selectedDate, timeline: timeline, isToday: isToday)
                            .padding(DesignTokens.Spacing.xl)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider().opacity(DesignTokens.Opacity.divider)
                    ScrollView { dayInfoOnly }
                        .frame(width: metrics.monthColumnWidth)
                }
            case .single:
                ScrollView {
                    VStack(spacing: 0) {
                        dayInfoOnly
                        permissionStrip
                        CalendarDayTimeline(day: selectedDate, timeline: timeline, isToday: isToday)
                            .frame(height: DesignTokens.Size.calendarHourHeight * CGFloat(12))
                            .padding(DesignTokens.Spacing.xl)
                    }
                }
            }
        }
    }

    /// 日 / 周视图里没授权日历时的引导条（已授权时不占位）
    @ViewBuilder
    private var permissionStrip: some View {
        if service.accessState != .authorized {
            CalendarEventsView(service: service, events: [], isToday: false)
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.top, DesignTokens.Spacing.md)
        }
    }

    // MARK: 所选日期

    /// 月视图右栏 / 单栏下方：信息卡 + 日程 + 近期节假日
    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            dayInfoCard
            CalendarEventsView(service: service, events: events, isToday: calendar.isDateInToday(selectedDate))
            upcomingCards
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 日视图右栏：日程已在时间轴里，这里只放信息卡与近期节假日
    private var dayInfoOnly: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            dayInfoCard
            upcomingCards
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dayInfoCard: some View {
        let civil = CivilDate(selectedDate, calendar: calendar)
        return DayInfoCard(
            date: selectedDate,
            day: AlmanacCache.shared.day(for: civil),
            status: showHolidays ? holidays.status(on: civil) : nil,
            weekNumber: showWeekNumber
                ? CalendarFormatting.weekNumber(for: selectedDate, calendar: calendar) : nil,
            showAlmanac: showAlmanac)
    }

    @ViewBuilder
    private var upcomingCards: some View {
        if showHolidays {
            UpcomingHolidaysCard(periods: holidays.upcoming(from: today, limit: 3), today: today)
        }
        if showAlmanac && !observances.isEmpty {
            UpcomingObservancesCard(observances: observances, today: today)
        }
    }
}
