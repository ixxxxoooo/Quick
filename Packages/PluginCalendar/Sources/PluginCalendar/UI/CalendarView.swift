// CalendarView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickUI
import SwiftUI

/// 日历看板主视图：左侧月历网格（含农历、节气、节假日、日程圆点）+ 右侧选中日详情与系统日程列表
struct CalendarView: View {

    let service: CalendarService

    @AppStorage(PluginSettingKey.Calendar.showWeekNumber) private var showWeekNumber = false
    @AppStorage(PluginSettingKey.Calendar.autoExtractMeetingLinks) private var autoExtractLinks = true

    /// 当前展示的月份基准日期
    @State private var displayedMonth: Date = Date()
    /// 当前选中的日期
    @State private var selectedDate: Date = Date()
    /// 当前月历网格（42 天）范围内的系统日历事件
    @State private var gridEvents: [CalendarEvent] = []
    /// 鼠标悬停的单元格 ID
    @State private var hoveredCellID: TimeInterval?

    @FocusState private var isFocused: Bool

    private var gregorian: Calendar {
        CalendarFormatting.mondayFirstGregorianCalendar()
    }

    /// 当前月份的 6 行 × 7 列网格
    private var weekRows: [CalendarWeekRow] {
        CalendarFormatting.monthGrid(for: displayedMonth)
    }

    /// 当前选中日期的完整日历信息
    private var selectedDayCell: CalendarDayCell {
        CalendarFormatting.dayCell(for: selectedDate, referenceMonth: displayedMonth)
    }

    /// 当前选中日期当天的事件列表
    private var selectedDayEvents: [CalendarEvent] {
        let cal = gregorian
        return CalendarEvent.sortedByStart(
            gridEvents.filter { $0.occurs(on: selectedDate, calendar: cal) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            monthBoard
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(DesignTokens.Colors.hairline)
                .frame(width: DesignTokens.Size.hairline)

            detailSidebar
                .frame(width: DesignTokens.Size.Calendar.detailSidebarWidth)
                .frame(maxHeight: .infinity)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            isFocused = true
            service.refreshAuthorizationStatus()
        }
        .task(id: reloadTaskKey) {
            await loadGridEvents()
        }
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { _ in
            moveSelectedDay(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { _ in
            moveSelectedDay(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in
            moveSelectedDay(by: -7)
            return .handled
        }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in
            moveSelectedDay(by: 7)
            return .handled
        }
    }

    /// 驱动月份事件重新加载的复合键
    private var reloadTaskKey: String {
        let comps = gregorian.dateComponents([.year, .month], from: displayedMonth)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(service.changeToken)-\(service.hasAccess)"
    }

    // MARK: - 左侧：月历网格看板

    private var monthBoard: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            monthHeaderBar
            weekdayHeaderRow
            monthGridBody
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    /// 月历顶部导航栏：公历年月 + 干支生肖年 + 周数 + 上月/今天/下月按钮
    private var monthHeaderBar: some View {
        let monthCell = CalendarFormatting.dayCell(for: displayedMonth)
        let selectedWeek = gregorian.component(.weekOfYear, from: selectedDate)

        return HStack(spacing: DesignTokens.Spacing.sm) {
            Text(CalendarFormatting.monthTitle(for: displayedMonth))
                .font(DesignTokens.Typography.panelTitle)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Text(monthCell.cyclicalYearText)
                .font(DesignTokens.Typography.keyCap)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(
                    Capsule(style: .continuous)
                        .fill(DesignTokens.Colors.controlSurface)
                )

            if showWeekNumber {
                Text("第 \(selectedWeek) 周")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Spacer(minLength: 0)

            HStack(spacing: DesignTokens.Spacing.xs) {
                navIconButton(systemImage: "chevron.left", label: "上个月") {
                    shiftMonth(by: -1)
                }

                Button {
                    jumpToToday()
                } label: {
                    Text("今天")
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .frame(height: DesignTokens.Size.windowControlButton)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap, style: .continuous)
                                .fill(DesignTokens.Colors.controlSurface)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                navIconButton(systemImage: "chevron.right", label: "下个月") {
                    shiftMonth(by: 1)
                }
            }
        }
    }

    private func navIconButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(DesignTokens.Typography.windowControlIcon)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(
                    width: DesignTokens.Size.windowControlButton,
                    height: DesignTokens.Size.windowControlButton
                )
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap, style: .continuous)
                        .fill(DesignTokens.Colors.controlSurface)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    /// 星期表头行（周一至周日，可选周数列）
    private var weekdayHeaderRow: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            if showWeekNumber {
                Text("周")
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(width: DesignTokens.Size.Calendar.weekColumnWidth)
            }

            ForEach(Array(CalendarFormatting.weekdayHeaders.enumerated()), id: \.offset) { idx, title in
                Text(title)
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(
                        idx >= 5
                            ? DesignTokens.Colors.textTertiary
                            : DesignTokens.Colors.textSecondary
                    )
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, DesignTokens.Spacing.xxs)
    }

    /// 6 行 × 7 列月历网格
    private var monthGridBody: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            ForEach(weekRows) { row in
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    if showWeekNumber {
                        Text("\(row.weekOfYear)")
                            .font(DesignTokens.Typography.compactKeyCap)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .frame(width: DesignTokens.Size.Calendar.weekColumnWidth)
                    }

                    ForEach(row.days) { cell in
                        dayCellView(cell)
                    }
                }
            }
        }
    }

    /// 单个日期格视图
    private func dayCellView(_ cell: CalendarDayCell) -> some View {
        let isSelected = gregorian.isDate(cell.date, inSameDayAs: selectedDate)
        let isHovered = hoveredCellID == cell.id
        let dayEvents = events(on: cell.date)

        return Button {
            selectDay(cell)
        } label: {
            VStack(spacing: DesignTokens.Spacing.xxs) {
                Text("\(cell.day)")
                    .font(DesignTokens.Typography.rowTitle)
                    .fontWeight(cell.isToday || isSelected ? .semibold : .regular)
                    .foregroundStyle(dayNumberColor(for: cell, isSelected: isSelected))

                Text(cell.subtitle)
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(subtitleColor(for: cell, isSelected: isSelected))
                    .lineLimit(1)

                // 系统日历事件指示点（固定占位高度，避免有无事件时文字上下偏移）
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    ForEach(Array(dayEvents.prefix(3).enumerated()), id: \.offset) { _, event in
                        Circle()
                            .fill(eventColor(for: event))
                            .frame(
                                width: DesignTokens.Size.Calendar.eventDot,
                                height: DesignTokens.Size.Calendar.eventDot
                            )
                    }
                }
                .frame(height: DesignTokens.Size.Calendar.eventDot)
            }
            .frame(maxWidth: .infinity)
            .frame(height: DesignTokens.Size.Calendar.cellHeight)
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                    .fill(cellBackground(for: cell, isSelected: isSelected, isHovered: isHovered))
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: DesignTokens.Size.hairline)
                } else if cell.isToday {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: DesignTokens.Size.hairline)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let mark = cell.workdayMark {
                    workdayBadgeView(mark, isCurrentMonth: cell.isCurrentMonth)
                        .padding(DesignTokens.Spacing.xxs)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredCellID = cell.id
            } else if hoveredCellID == cell.id {
                hoveredCellID = nil
            }
        }
    }

    /// 右上角法定「休 / 班」角标
    private func workdayBadgeView(_ mark: CalendarWorkdayMark, isCurrentMonth: Bool) -> some View {
        let color: Color = mark == .holiday ? DesignTokens.Colors.success : DesignTokens.Colors.warning
        return Text(mark.rawValue)
            .font(DesignTokens.Typography.compactKeyCap)
            .foregroundStyle(color.opacity(isCurrentMonth ? 1.0 : 0.45))
            .frame(
                width: DesignTokens.Size.Calendar.workdayBadge,
                height: DesignTokens.Size.Calendar.workdayBadge
            )
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap / 2, style: .continuous)
                    .fill(color.opacity(isCurrentMonth ? 0.16 : 0.08))
            )
    }

    private func dayNumberColor(for cell: CalendarDayCell, isSelected: Bool) -> Color {
        if cell.isToday {
            return Color.accentColor
        }
        if !cell.isCurrentMonth {
            return DesignTokens.Colors.textTertiary.opacity(0.5)
        }
        if cell.isWeekend {
            return DesignTokens.Colors.textSecondary
        }
        return DesignTokens.Colors.textPrimary
    }

    private func subtitleColor(for cell: CalendarDayCell, isSelected: Bool) -> Color {
        if !cell.isCurrentMonth {
            return (cell.isSubtitleHighlighted ? Color.accentColor : DesignTokens.Colors.textTertiary)
                .opacity(0.45)
        }
        if cell.isSubtitleHighlighted {
            return Color.accentColor
        }
        return isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary
    }

    private func cellBackground(for cell: CalendarDayCell, isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.20)
        }
        if cell.isToday {
            return Color.accentColor.opacity(0.08)
        }
        if isHovered {
            return DesignTokens.Colors.rowHover
        }
        return .clear
    }

    // MARK: - 右侧：选中日黄历详情 + 当日系统日程列表

    private var detailSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectedDaySummaryCard
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.md)

            Rectangle()
                .fill(DesignTokens.Colors.hairline)
                .frame(height: DesignTokens.Size.hairline)

            eventsSection
        }
    }

    /// 选中日期的公历、农历、节气与节假日详情卡片
    private var selectedDaySummaryCard: some View {
        let cell = selectedDayCell
        let relativeText = CalendarFormatting.relativeDayDescription(for: cell.date)
        let weekdayText = CalendarFormatting.weekdayTitle(for: cell.date)

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
                Text("\(cell.month)月\(cell.day)日")
                    .font(DesignTokens.Typography.panelTitle)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Text(weekdayText)
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                Spacer(minLength: 0)

                Text(relativeText)
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(cell.isToday ? Color.accentColor : DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                cell.isToday
                                    ? Color.accentColor.opacity(0.16)
                                    : DesignTokens.Colors.controlSurface
                            )
                    )
            }

            Text(cell.fullLunarDescription)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            if !cell.festivals.isEmpty || cell.solarTerm != nil || cell.workdayMark != nil {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    if let mark = cell.workdayMark {
                        tagChip(
                            mark == .holiday ? "法定休假" : "调休上班",
                            tint: mark == .holiday
                                ? DesignTokens.Colors.success
                                : DesignTokens.Colors.warning
                        )
                    }
                    if let term = cell.solarTerm {
                        tagChip("节气 · \(term)", tint: DesignTokens.Colors.progress)
                    }
                    ForEach(cell.festivals, id: \.self) { festival in
                        tagChip(festival, tint: Color.accentColor)
                    }
                }
                .padding(.top, DesignTokens.Spacing.xxs)
            }
        }
    }

    private func tagChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(DesignTokens.Typography.compactKeyCap)
            .foregroundStyle(tint)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }

    // MARK: - 系统日历事件列表区

    private var eventsSection: some View {
        let dayEvents = selectedDayEvents

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text("日程安排")
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                if service.hasAccess && !dayEvents.isEmpty {
                    Text("\(dayEvents.count)")
                        .font(DesignTokens.Typography.compactKeyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(
                            Capsule(style: .continuous)
                                .fill(DesignTokens.Colors.controlSurface)
                        )
                }

                Spacer(minLength: 0)

                Button {
                    service.openSystemCalendarApp()
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        Image(systemName: "calendar")
                            .font(DesignTokens.Typography.compactIcon)
                        Text("打开日历")
                            .font(DesignTokens.Typography.compactKeyCap)
                    }
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("在系统「日历」应用中查看")
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            if !service.hasAccess {
                permissionPromptView
            } else if dayEvents.isEmpty {
                emptyEventsView
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(dayEvents) { event in
                            eventCardView(event)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.bottom, DesignTokens.Spacing.md)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 单条日程卡片
    private func eventCardView(_ event: CalendarEvent) -> some View {
        let barColor = eventColor(for: event)
        let meetingURL = autoExtractLinks ? event.meetingURL : nil

        return HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Capsule(style: .continuous)
                .fill(barColor)
                .frame(width: DesignTokens.Size.Calendar.eventBarWidth)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(event.title)
                    .font(DesignTokens.Typography.rowTitle)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(event.timeRange)
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)

                    if !event.calendarTitle.isEmpty {
                        Text("· \(event.calendarTitle)")
                            .font(DesignTokens.Typography.compactKeyCap)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }

                if let location = event.location {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        Image(systemName: "location")
                            .font(DesignTokens.Typography.compactIcon)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text(location)
                            .font(DesignTokens.Typography.compactKeyCap)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            if let meetingURL {
                Button {
                    NSWorkspace.shared.open(meetingURL)
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        Image(systemName: "video.fill")
                            .font(DesignTokens.Typography.compactIcon)
                        Text("加入")
                            .font(DesignTokens.Typography.compactKeyCap)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("打开会议链接")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(DesignTokens.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: DesignTokens.Size.hairline)
        )
    }

    /// 当日无日程的空状态
    private var emptyEventsView: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "calendar.badge.checkmark")
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("当日无日程安排")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.lg)
    }

    /// 未获日历权限时的引导状态
    private var permissionPromptView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(DesignTokens.Colors.warning)

            Text("需要日历访问权限以显示系统日程")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: DesignTokens.Spacing.sm) {
                if service.authorizationState == .notDetermined {
                    Button {
                        service.requestAccess()
                    } label: {
                        Text("授权访问日历")
                            .font(DesignTokens.Typography.keyCap)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accentColor.opacity(0.15))
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        service.openSystemCalendarPrivacySettings()
                    } label: {
                        Text("打开系统设置")
                            .font(DesignTokens.Typography.keyCap)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accentColor.opacity(0.15))
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.lg)
    }

    // MARK: - 交互与数据加载

    private func selectDay(_ cell: CalendarDayCell) {
        selectedDate = cell.date
        if !cell.isCurrentMonth {
            displayedMonth = cell.date
        }
    }

    private func shiftMonth(by delta: Int) {
        guard let nextMonth = gregorian.date(byAdding: .month, value: delta, to: displayedMonth) else {
            return
        }
        displayedMonth = nextMonth
        // 若切换到新月份，选中该月同一日（或月末）
        let targetComps = gregorian.dateComponents([.year, .month], from: nextMonth)
        let currentDay = gregorian.component(.day, from: selectedDate)
        var newSelectedComps = DateComponents()
        newSelectedComps.year = targetComps.year
        newSelectedComps.month = targetComps.month
        newSelectedComps.day = 1
        if let firstOfTarget = gregorian.date(from: newSelectedComps),
            let range = gregorian.range(of: .day, in: .month, for: firstOfTarget)
        {
            newSelectedComps.day = min(currentDay, range.count)
            if let aligned = gregorian.date(from: newSelectedComps) {
                selectedDate = aligned
            }
        }
    }

    private func jumpToToday() {
        let now = Date()
        displayedMonth = now
        selectedDate = gregorian.startOfDay(for: now)
    }

    private func moveSelectedDay(by days: Int) {
        guard let nextDate = gregorian.date(byAdding: .day, value: days, to: selectedDate) else {
            return
        }
        selectedDate = nextDate
        let currentMonth = gregorian.dateComponents([.year, .month], from: displayedMonth)
        let nextMonth = gregorian.dateComponents([.year, .month], from: nextDate)
        if currentMonth.year != nextMonth.year || currentMonth.month != nextMonth.month {
            displayedMonth = nextDate
        }
    }

    private func loadGridEvents() async {
        let rows = weekRows
        guard let firstDay = rows.first?.days.first?.date,
            let lastDay = rows.last?.days.last?.date,
            let rangeEnd = gregorian.date(byAdding: .day, value: 1, to: lastDay)
        else {
            gridEvents = []
            return
        }
        gridEvents = await service.events(from: firstDay, to: rangeEnd)
    }

    private func events(on date: Date) -> [CalendarEvent] {
        let cal = gregorian
        return gridEvents.filter { $0.occurs(on: date, calendar: cal) }
    }

    /// 解析事件的十六进制颜色（如 `#3B82F6`），缺省退回语义进度色
    private func eventColor(for event: CalendarEvent) -> Color {
        let hex = event.calendarColor
        guard hex.hasPrefix("#"), hex.count == 7,
            let value = UInt32(hex.dropFirst(), radix: 16)
        else {
            return DesignTokens.Colors.progress
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
