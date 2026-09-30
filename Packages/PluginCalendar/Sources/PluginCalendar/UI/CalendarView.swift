// CalendarView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickUI
import SwiftUI

/// 日历看板主视图：左侧日/月/年多视图看板 + 右侧选中日详情、传统黄历与系统日程管理（支持新建系统日程）
struct CalendarView: View {

    let service: CalendarService

    @AppStorage(PluginSettingKey.Calendar.showWeekNumber) private var showWeekNumber = false
    @AppStorage(PluginSettingKey.Calendar.autoExtractMeetingLinks) private var autoExtractLinks = true
    @AppStorage(CalendarPreferences.showLunar) private var showLunar = true
    @AppStorage(CalendarPreferences.showBuiltInHolidays) private var showBuiltInHolidays = true
    @AppStorage(CalendarPreferences.showAlmanac) private var showAlmanac = true
    @AppStorage(CalendarPreferences.showSystemEvents) private var showSystemEvents = true
    @AppStorage(CalendarPreferences.disabledCalendarIDs) private var disabledCalendarIDs = ""

    /// 当前看板视图模式（日 / 月 / 年）
    @State private var boardMode: CalendarBoardMode = .month
    /// 当前展示的月份/年份基准日期
    @State private var displayedMonth: Date = Date()
    /// 当前选中的日期
    @State private var selectedDate: Date = Date()
    /// 按当天零点时间戳预聚合的系统日历事件字典，O(1) 查询避免网格重绘遍历
    @State private var eventsByDay: [TimeInterval: [CalendarEvent]] = [:]
    /// 鼠标悬停的单元格 ID
    @State private var hoveredCellID: TimeInterval?

    // MARK: - 新建系统日程表单状态

    @State private var isCreatingEvent = false
    @State private var writableCalendars: [CalendarSource] = []
    @State private var draftTitle = ""
    @State private var draftCalendarID = ""
    @State private var draftIsAllDay = false
    @State private var draftStartDate = Date()
    @State private var draftEndDate = Date()
    @State private var draftLocation = ""
    @State private var draftNotes = ""
    @State private var createErrorMessage: String?

    @FocusState private var isFocused: Bool
    @FocusState private var isTitleFieldFocused: Bool

    private static let gregorianCalendar = CalendarFormatting.mondayFirstGregorianCalendar()

    private var gregorian: Calendar {
        Self.gregorianCalendar
    }

    /// 当前月份的 6 行 × 7 列网格（内部带锁缓存，O(1) 命中）
    private var weekRows: [CalendarWeekRow] {
        CalendarFormatting.monthGrid(for: displayedMonth)
    }

    /// 当前年份的 12 个迷你月历（内部带锁缓存，O(1) 命中）
    private var yearMiniMonths: [CalendarMiniMonth] {
        CalendarFormatting.yearMonths(for: displayedMonth)
    }

    /// 当前选中日期的完整日历信息
    private var selectedDayCell: CalendarDayCell {
        CalendarFormatting.dayCell(for: selectedDate, referenceMonth: displayedMonth)
    }

    /// 当前选中日期的传统黄历信息
    private var selectedAlmanac: CalendarAlmanac {
        CalendarFormatting.almanac(for: selectedDate)
    }

    /// 当前选中日期当天的事件列表（O(1) 字典读取）
    private var selectedDayEvents: [CalendarEvent] {
        guard showSystemEvents else { return [] }
        let dayKey = gregorian.startOfDay(for: selectedDate).timeIntervalSince1970
        return eventsByDay[dayKey] ?? []
    }

    var body: some View {
        HStack(spacing: 0) {
            leftBoardContainer
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Rectangle()
                .fill(DesignTokens.Colors.hairline)
                .frame(width: DesignTokens.Size.hairline)

            detailSidebar
                .frame(width: DesignTokens.Size.Calendar.detailSidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
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
            guard !isCreatingEvent else { return .ignored }
            moveSelectedDay(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { _ in
            guard !isCreatingEvent else { return .ignored }
            moveSelectedDay(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in
            guard !isCreatingEvent else { return .ignored }
            moveSelectedDay(by: -7)
            return .handled
        }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in
            guard !isCreatingEvent else { return .ignored }
            moveSelectedDay(by: 7)
            return .handled
        }
    }

    /// 驱动月份事件重新加载的复合键
    private var reloadTaskKey: String {
        let comps = gregorian.dateComponents([.year, .month], from: displayedMonth)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(service.changeToken)-\(service.hasAccess)-\(showSystemEvents)-\(disabledCalendarIDs)"
    }

    // MARK: - 左侧：多模式日历看板（日 / 月 / 年）

    private var leftBoardContainer: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            boardHeaderBar

            switch boardMode {
            case .day:
                dayBoardBody
            case .month:
                weekdayHeaderRow
                monthGridBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .year:
                yearBoardBody
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    /// 看板顶部导航栏：标题 + 干支纪年 + 周数 + 视图切换器（日/月/年） + 前后步进按钮
    private var boardHeaderBar: some View {
        let refDate = boardMode == .day ? selectedDate : displayedMonth
        let refCell = CalendarFormatting.dayCell(for: refDate)
        let selectedWeek = gregorian.component(.weekOfYear, from: selectedDate)

        return HStack(spacing: DesignTokens.Spacing.sm) {
            Text(headerTitleText)
                .font(DesignTokens.Typography.panelTitle)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)

            if showLunar {
                Text(refCell.cyclicalYearText)
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DesignTokens.Colors.controlSurface)
                    )
                    .lineLimit(1)
            }

            if showWeekNumber && boardMode != .year {
                Text("第 \(selectedWeek) 周")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            modeSwitcher

            HStack(spacing: DesignTokens.Spacing.xs) {
                navIconButton(systemImage: "chevron.left", label: previousStepLabel) {
                    stepBoard(by: -1)
                }

                Button {
                    jumpToToday()
                } label: {
                    Text("今天")
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .frame(height: DesignTokens.Size.windowControlButton)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap, style: .continuous)
                                .fill(DesignTokens.Colors.controlSurface)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                navIconButton(systemImage: "chevron.right", label: nextStepLabel) {
                    stepBoard(by: 1)
                }
            }
        }
    }

    private var headerTitleText: String {
        switch boardMode {
        case .day:
            return CalendarFormatting.fullDateTitle(for: selectedDate)
        case .month:
            return CalendarFormatting.monthTitle(for: displayedMonth)
        case .year:
            return CalendarFormatting.yearTitle(for: displayedMonth)
        }
    }

    private var previousStepLabel: String {
        switch boardMode {
        case .day: return "上一天"
        case .month: return "上个月"
        case .year: return "上一年"
        }
    }

    private var nextStepLabel: String {
        switch boardMode {
        case .day: return "下一天"
        case .month: return "下个月"
        case .year: return "下一年"
        }
    }

    /// 日 / 月 / 年 视图模式分段切换器
    private var modeSwitcher: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            ForEach(CalendarBoardMode.allCases) { mode in
                let isCurrent = boardMode == mode
                Button {
                    boardMode = mode
                } label: {
                    Text(mode.rawValue)
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(
                            isCurrent
                                ? Color.accentColor
                                : DesignTokens.Colors.textSecondary
                        )
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .frame(height: DesignTokens.Size.windowControlButton)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap, style: .continuous)
                                .fill(
                                    isCurrent
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.clear
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignTokens.Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap, style: .continuous)
                .fill(DesignTokens.Colors.controlSurface)
        )
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

    // MARK: - 模式一：日视图（大字日历台历 + 完整黄历宜忌面板）

    private var dayBoardBody: some View {
        let cell = selectedDayCell
        let almanac = selectedAlmanac
        let weekdayText = CalendarFormatting.weekdayTitle(for: cell.date)
        let relativeText = CalendarFormatting.relativeDayDescription(for: cell.date)

        return ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(alignment: .center, spacing: DesignTokens.Spacing.xl) {
                    Text("\(cell.day)")
                        .font(DesignTokens.Typography.calendarHeroDay)
                        .foregroundStyle(cell.isToday ? Color.accentColor : DesignTokens.Colors.textPrimary)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Text(weekdayText)
                                .font(DesignTokens.Typography.panelTitle)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)

                            Text(relativeText)
                                .font(DesignTokens.Typography.keyCap)
                                .foregroundStyle(
                                    cell.isToday ? Color.accentColor : DesignTokens.Colors.textSecondary
                                )
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

                        if showLunar {
                            Text("农历 \(cell.lunarMonthText)\(cell.lunarDayText) · \(cell.cyclicalYearText)")
                                .font(DesignTokens.Typography.rowTitle)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }

                        dayBadgesRow(for: cell)
                    }

                    Spacer(minLength: 0)
                }
                .padding(DesignTokens.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                        .fill(DesignTokens.Colors.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                        .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: DesignTokens.Size.hairline)
                )

                if showAlmanac {
                    fullAlmanacCard(almanac)
                }
            }
            .padding(.top, DesignTokens.Spacing.xs)
        }
        .scrollIndicators(.never)
    }

    /// 完整传统黄历卡片（用于「日」视图）
    private func fullAlmanacCard(_ almanac: CalendarAlmanac) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(almanac.pillarSummary)
                    .font(DesignTokens.Typography.rowTitle)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Spacer(minLength: 0)

                tagChip("值神 · \(almanac.dutyTwelveGod)", tint: DesignTokens.Colors.progress)
                tagChip(almanac.clashAndSha, tint: DesignTokens.Colors.warning)
            }

            Rectangle()
                .fill(DesignTokens.Colors.hairline)
                .frame(height: DesignTokens.Size.hairline)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                almanacYiJiRow(
                    badge: "宜",
                    items: almanac.yi,
                    tint: DesignTokens.Colors.success
                )

                almanacYiJiRow(
                    badge: "忌",
                    items: almanac.ji,
                    tint: DesignTokens.Colors.destructive
                )
            }

            Rectangle()
                .fill(DesignTokens.Colors.hairline)
                .frame(height: DesignTokens.Size.hairline)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("吉神方位")
                        .font(DesignTokens.Typography.compactKeyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(almanac.godDirections)
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("彭祖百忌")
                        .font(DesignTokens.Typography.compactKeyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(almanac.pengZuTaboo)
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(DesignTokens.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: DesignTokens.Size.hairline)
        )
    }

    private func almanacYiJiRow(badge: String, items: [String], tint: Color) -> some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
            Text(badge)
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(tint)
                .frame(
                    width: DesignTokens.Size.Calendar.almanacBadge,
                    height: DesignTokens.Size.Calendar.almanacBadge
                )
                .background(
                    Circle()
                        .fill(tint.opacity(0.16))
                )

            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap / 2, style: .continuous)
                                .fill(DesignTokens.Colors.controlSurface)
                        )
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 模式二：月视图（6 行 × 7 列月历网格，垂直自适应铺满）

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

    /// 6 行 × 7 列月历网格（自适应填满剩余高度，消除顶部/底部空白）
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// 单个日期格视图
    private func dayCellView(_ cell: CalendarDayCell) -> some View {
        let isSelected = gregorian.isDate(cell.date, inSameDayAs: selectedDate)
        let isHovered = hoveredCellID == cell.id
        let dayEvents = showSystemEvents ? (eventsByDay[cell.id] ?? []) : []
        let sub = cell.displaySubtitle(showLunar: showLunar, showHolidays: showBuiltInHolidays)

        return Button {
            selectDay(cell)
        } label: {
            VStack(spacing: DesignTokens.Spacing.xxs) {
                Text("\(cell.day)")
                    .font(DesignTokens.Typography.rowTitle)
                    .fontWeight(cell.isToday || isSelected ? .semibold : .regular)
                    .foregroundStyle(dayNumberColor(for: cell, isSelected: isSelected))

                if !sub.text.isEmpty {
                    Text(sub.text)
                        .font(DesignTokens.Typography.compactKeyCap)
                        .foregroundStyle(
                            subtitleColor(
                                for: cell,
                                isSelected: isSelected,
                                isHighlighted: sub.isHighlighted
                            )
                        )
                        .lineLimit(1)
                }

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                if showBuiltInHolidays, let mark = cell.workdayMark {
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

    // MARK: - 模式三：年视图（12 个月轻量迷你卡片，零按钮嵌套消除卡顿）

    private var yearBoardBody: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.sm),
            count: 3
        )

        return ScrollView {
            LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.sm) {
                ForEach(yearMiniMonths) { mini in
                    miniMonthCard(mini)
                }
            }
            .padding(.vertical, DesignTokens.Spacing.xxs)
        }
        .scrollIndicators(.never)
    }

    private func miniMonthCard(_ mini: CalendarMiniMonth) -> some View {
        let isSelectedMonth =
            gregorian.component(.year, from: selectedDate) == mini.year
            && gregorian.component(.month, from: selectedDate) == mini.month

        return Button {
            selectMonthFromYearView(mini)
        } label: {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Text(mini.title)
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(
                            isSelectedMonth ? Color.accentColor : DesignTokens.Colors.textPrimary
                        )
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(DesignTokens.Typography.compactIcon)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }

                HStack(spacing: 0) {
                    ForEach(Array(CalendarFormatting.weekdayHeaders.enumerated()), id: \.offset) { _, w in
                        Text(w)
                            .font(DesignTokens.Typography.compactKeyCap)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }

                VStack(spacing: DesignTokens.Spacing.xxs) {
                    ForEach(mini.weeks) { row in
                        HStack(spacing: 0) {
                            ForEach(row.days) { cell in
                                miniDayLabel(cell)
                            }
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .fill(DesignTokens.Colors.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .strokeBorder(
                        isSelectedMonth ? Color.accentColor.opacity(0.45) : DesignTokens.Colors.cardStroke,
                        lineWidth: DesignTokens.Size.hairline
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func miniDayLabel(_ cell: CalendarDayCell) -> some View {
        let isSelected = cell.isCurrentMonth && gregorian.isDate(cell.date, inSameDayAs: selectedDate)
        let isHoliday = cell.isCurrentMonth && showBuiltInHolidays && cell.workdayMark == .holiday

        return Text(cell.isCurrentMonth ? "\(cell.day)" : "")
            .font(DesignTokens.Typography.compactKeyCap)
            .foregroundStyle(
                cell.isToday && cell.isCurrentMonth
                    ? Color.accentColor
                    : isSelected
                        ? DesignTokens.Colors.textPrimary
                        : isHoliday
                            ? DesignTokens.Colors.success
                            : cell.isWeekend
                                ? DesignTokens.Colors.textTertiary
                                : DesignTokens.Colors.textSecondary
            )
            .frame(maxWidth: .infinity)
            .frame(height: DesignTokens.Size.Calendar.miniCellHeight)
            .background(
                Circle()
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.25)
                            : (cell.isToday && cell.isCurrentMonth)
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                    )
            )
    }

    // MARK: - 颜色辅助

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

    private func subtitleColor(
        for cell: CalendarDayCell,
        isSelected: Bool,
        isHighlighted: Bool
    ) -> Color {
        if !cell.isCurrentMonth {
            return (isHighlighted ? Color.accentColor : DesignTokens.Colors.textTertiary)
                .opacity(0.45)
        }
        if isHighlighted {
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

    // MARK: - 右侧：选中日黄历详情 + 当日系统日程列表 / 新建日程表单

    private var detailSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectedDaySummaryCard
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.md)

            Rectangle()
                .fill(DesignTokens.Colors.hairline)
                .frame(height: DesignTokens.Size.hairline)

            if showSystemEvents {
                eventsSection
            } else {
                sidebarAlmanacDetailSection
            }
        }
    }

    /// 选中日期的公历、农历、节气、节假日与精简黄历宜忌卡片
    private var selectedDaySummaryCard: some View {
        let cell = selectedDayCell
        let almanac = selectedAlmanac
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

            if showLunar {
                Text(cell.fullLunarDescription)
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            dayBadgesRow(for: cell)

            if showAlmanac && showSystemEvents && boardMode != .day && !isCreatingEvent {
                compactSidebarAlmanacView(almanac)
                    .padding(.top, DesignTokens.Spacing.xxs)
            }
        }
    }

    /// 节气、内置节假日与调休标签行（受 `showLunar` 与 `showBuiltInHolidays` 控制）
    @ViewBuilder
    private func dayBadgesRow(for cell: CalendarDayCell) -> some View {
        let hasWorkdayMark = showBuiltInHolidays && cell.workdayMark != nil
        let hasSolarTerm = showLunar && cell.solarTerm != nil
        let hasFestivals = showBuiltInHolidays && !cell.festivals.isEmpty

        if hasWorkdayMark || hasSolarTerm || hasFestivals {
            HStack(spacing: DesignTokens.Spacing.xs) {
                if showBuiltInHolidays, let mark = cell.workdayMark {
                    tagChip(
                        mark == .holiday ? "法定休假" : "调休上班",
                        tint: mark == .holiday
                            ? DesignTokens.Colors.success
                            : DesignTokens.Colors.warning
                    )
                }
                if showLunar, let term = cell.solarTerm {
                    tagChip("节气 · \(term)", tint: DesignTokens.Colors.progress)
                }
                if showBuiltInHolidays {
                    ForEach(cell.festivals.prefix(2), id: \.self) { festival in
                        tagChip(festival, tint: Color.accentColor)
                    }
                }
            }
            .padding(.top, DesignTokens.Spacing.xxs)
        }
    }

    /// 侧边栏紧凑黄历（干支值神冲煞 + 宜忌简表）
    private func compactSidebarAlmanacView(_ almanac: CalendarAlmanac) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text("\(almanac.monthStemBranch) \(almanac.dayStemBranch) · \(almanac.dutyTwelveGod) · \(almanac.clashAndSha)")
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .lineLimit(1)

            HStack(spacing: DesignTokens.Spacing.xs) {
                Text("宜")
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(DesignTokens.Colors.success)
                    .padding(.horizontal, DesignTokens.Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap / 2, style: .continuous)
                            .fill(DesignTokens.Colors.success.opacity(0.14))
                    )
                Text(almanac.yi.prefix(4).joined(separator: " · "))
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                Text("忌")
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(DesignTokens.Colors.destructive)
                    .padding(.horizontal, DesignTokens.Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap / 2, style: .continuous)
                            .fill(DesignTokens.Colors.destructive.opacity(0.14))
                    )
                Text(almanac.ji.prefix(4).joined(separator: " · "))
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    /// 当用户在设置中关闭「系统日历日程」时，右侧下方展示完整黄历详情或提示
    private var sidebarAlmanacDetailSection: some View {
        let almanac = selectedAlmanac
        return ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                if showAlmanac {
                    Text("传统黄历")
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)

                    Text(almanac.pillarSummary)
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)

                    HStack(spacing: DesignTokens.Spacing.xs) {
                        tagChip("值神 · \(almanac.dutyTwelveGod)", tint: DesignTokens.Colors.progress)
                        tagChip(almanac.clashAndSha, tint: DesignTokens.Colors.warning)
                    }

                    compactSidebarAlmanacView(almanac)

                    Text(almanac.godDirections)
                        .font(DesignTokens.Typography.compactKeyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)

                    Text("彭祖百忌：\(almanac.pengZuTaboo)")
                        .font(DesignTokens.Typography.compactKeyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                } else {
                    Text("系统日历日程已在设置中停用")
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)
        }
        .scrollIndicators(.never)
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

    // MARK: - 系统日历事件列表与新建日程区

    private var eventsSection: some View {
        let dayEvents = selectedDayEvents

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(isCreatingEvent ? "新建系统日程" : "日程安排")
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                if !isCreatingEvent && service.hasAccess && !dayEvents.isEmpty {
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

                if service.hasAccess && !isCreatingEvent {
                    Button {
                        beginCreateEvent()
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.xxs) {
                            Image(systemName: "plus")
                                .font(DesignTokens.Typography.compactIcon)
                            Text("新建")
                                .font(DesignTokens.Typography.compactKeyCap)
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("向 macOS 系统日历添加日程")
                }

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
            } else if isCreatingEvent {
                createEventFormView
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

    /// 内联新建系统日程表单（直接写入 macOS 系统日历）
    private var createEventFormView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                TextField("日程标题（必填）", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.rowTitle)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .focused($isTitleFieldFocused)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                            .fill(DesignTokens.Colors.controlSurface)
                    )
                    .onSubmit {
                        submitNewEvent()
                    }

                if !writableCalendars.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text("日历")
                            .font(DesignTokens.Typography.compactKeyCap)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)

                        Spacer(minLength: 0)

                        Picker("", selection: $draftCalendarID) {
                            ForEach(writableCalendars) { cal in
                                Text(cal.title).tag(cal.id)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }

                Toggle(isOn: $draftIsAllDay) {
                    Text("全天日程")
                        .font(DesignTokens.Typography.compactKeyCap)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                DatePicker(
                    "开始",
                    selection: $draftStartDate,
                    displayedComponents: draftIsAllDay ? [.date] : [.date, .hourAndMinute]
                )
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .controlSize(.small)
                .onChange(of: draftStartDate) { _, newStart in
                    if draftEndDate < newStart {
                        draftEndDate =
                            gregorian.date(byAdding: .hour, value: 1, to: newStart) ?? newStart
                    }
                }

                DatePicker(
                    "结束",
                    selection: $draftEndDate,
                    in: draftStartDate...,
                    displayedComponents: draftIsAllDay ? [.date] : [.date, .hourAndMinute]
                )
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .controlSize(.small)

                TextField("地点（选填）", text: $draftLocation)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                            .fill(DesignTokens.Colors.controlSurface)
                    )

                TextField("备注或会议链接（选填）", text: $draftNotes)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                            .fill(DesignTokens.Colors.controlSurface)
                    )
                    .onSubmit {
                        submitNewEvent()
                    }

                if let createErrorMessage {
                    Text(createErrorMessage)
                        .font(DesignTokens.Typography.compactKeyCap)
                        .foregroundStyle(DesignTokens.Colors.destructive)
                }

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button {
                        cancelCreateEvent()
                    } label: {
                        Text("取消")
                            .font(DesignTokens.Typography.keyCap)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                                    .fill(DesignTokens.Colors.controlSurface)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        submitNewEvent()
                    } label: {
                        Text("添加到系统日历")
                            .font(DesignTokens.Typography.keyCap)
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.16))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, DesignTokens.Spacing.xxs)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.md)
        }
        .scrollIndicators(.never)
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

    private func beginCreateEvent() {
        let writable = service.writableCalendars()
        writableCalendars = writable
        if draftCalendarID.isEmpty || !writable.contains(where: { $0.id == draftCalendarID }) {
            draftCalendarID = writable.first?.id ?? ""
        }
        let window = CalendarFormatting.defaultNewEventWindow(on: selectedDate)
        draftTitle = ""
        draftIsAllDay = false
        draftStartDate = window.start
        draftEndDate = window.end
        draftLocation = ""
        draftNotes = ""
        createErrorMessage = nil
        isCreatingEvent = true
        isTitleFieldFocused = true
    }

    private func cancelCreateEvent() {
        isCreatingEvent = false
        createErrorMessage = nil
        isFocused = true
    }

    private func submitNewEvent() {
        do {
            try service.createEvent(
                title: draftTitle,
                startDate: draftStartDate,
                endDate: draftEndDate,
                isAllDay: draftIsAllDay,
                calendarID: draftCalendarID.isEmpty ? nil : draftCalendarID,
                location: draftLocation,
                notes: draftNotes
            )
            // 若新建日程落在其他日期，自动跳转到该日期以立即展示刚添加的事件
            selectedDate = gregorian.startOfDay(for: draftStartDate)
            displayedMonth = draftStartDate
            isCreatingEvent = false
            createErrorMessage = nil
            isFocused = true
            Task {
                await loadGridEvents()
            }
        } catch {
            createErrorMessage = error.localizedDescription
        }
    }

    private func selectDay(_ cell: CalendarDayCell) {
        selectedDate = cell.date
        if !cell.isCurrentMonth {
            displayedMonth = cell.date
        }
        if isCreatingEvent {
            let window = CalendarFormatting.defaultNewEventWindow(on: cell.date)
            draftStartDate = window.start
            draftEndDate = window.end
        }
    }

    private func selectMonthFromYearView(_ mini: CalendarMiniMonth) {
        displayedMonth = mini.monthDate
        let currentDay = gregorian.component(.day, from: selectedDate)
        var newSelectedComps = DateComponents()
        newSelectedComps.year = mini.year
        newSelectedComps.month = mini.month
        newSelectedComps.day = 1
        if let firstOfTarget = gregorian.date(from: newSelectedComps),
            let range = gregorian.range(of: .day, in: .month, for: firstOfTarget)
        {
            newSelectedComps.day = min(currentDay, range.count)
            if let aligned = gregorian.date(from: newSelectedComps) {
                selectedDate = aligned
            }
        }
        boardMode = .month
    }

    private func stepBoard(by delta: Int) {
        switch boardMode {
        case .day:
            moveSelectedDay(by: delta)
        case .month:
            shiftMonth(by: delta)
        case .year:
            shiftYear(by: delta)
        }
    }

    private func shiftMonth(by delta: Int) {
        guard let nextMonth = gregorian.date(byAdding: .month, value: delta, to: displayedMonth) else {
            return
        }
        displayedMonth = nextMonth
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

    private func shiftYear(by delta: Int) {
        guard let nextYear = gregorian.date(byAdding: .year, value: delta, to: displayedMonth) else {
            return
        }
        displayedMonth = nextYear
        if let alignedSelected = gregorian.date(byAdding: .year, value: delta, to: selectedDate) {
            selectedDate = alignedSelected
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
        guard showSystemEvents else {
            eventsByDay = [:]
            return
        }
        let rows = weekRows
        guard let firstDay = rows.first?.days.first?.date,
            let lastDay = rows.last?.days.last?.date,
            let rangeEnd = gregorian.date(byAdding: .day, value: 1, to: lastDay)
        else {
            eventsByDay = [:]
            return
        }
        let fetched = await service.events(from: firstDay, to: rangeEnd)
        let cal = gregorian
        var grouped: [TimeInterval: [CalendarEvent]] = [:]
        for row in rows {
            for cell in row.days {
                let dayMatches = fetched.filter { $0.occurs(on: cell.date, calendar: cal) }
                if !dayMatches.isEmpty {
                    grouped[cell.id] = CalendarEvent.sortedByStart(dayMatches)
                }
            }
        }
        eventsByDay = grouped
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
