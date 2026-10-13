// CalendarView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickUI
import SwiftUI

/// 日历插件视图
///
/// 左：月历（农历小字、事件小圆点、可选周数列）；右：所选日期的日程。
/// 未授权日历时月历与农历仍可用，右侧给出授权入口 —— 授权由用户主动触发，不在启动时弹框。
struct CalendarView: View {

    let service: CalendarService

    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var events: [CalendarEvent] = []
    @State private var markedDays: Set<Date> = []

    @AppStorage(PluginSettingKey.Calendar.showWeekNumber) private var showWeekNumber = false
    @AppStorage(PluginSettingKey.Calendar.autoExtractMeetingLinks) private var extractsLinks = true

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            monthPanel
                .frame(width: DesignTokens.Size.calendarPanelWidth)

            Divider().opacity(0.3)

            dayPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { service.refreshAccessState() }
        .task(id: selectedDate) { reloadEvents() }
        .task(id: displayedMonth) { reloadMarks() }
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
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.xl)
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
            let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
            let isToday = calendar.isDateInToday(date)
            let hasEvents = markedDays.contains(calendar.startOfDay(for: date))
            Button {
                selectedDate = calendar.startOfDay(for: date)
            } label: {
                VStack(spacing: 0) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(DesignTokens.Typography.rowTitle)
                        .fontWeight(isToday ? .semibold : .regular)
                    Text(CalendarFormatting.lunarCellLabel(for: date))
                        .font(DesignTokens.Typography.compactKeyCap)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? DesignTokens.Colors.onAccent : DesignTokens.Colors.textTertiary)
                    Circle()
                        .fill(hasEvents ? (isSelected ? DesignTokens.Colors.onAccent : DesignTokens.Colors.progress) : .clear)
                        .frame(width: DesignTokens.Size.calendarDot, height: DesignTokens.Size.calendarDot)
                }
                .foregroundStyle(
                    isSelected
                        ? DesignTokens.Colors.onAccent
                        : (isToday ? DesignTokens.Colors.progress : DesignTokens.Colors.textPrimary)
                )
                .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.calendarCellHeight)
                .background {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                        .fill(isSelected ? DesignTokens.Colors.progress : .clear)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(for: date, hasEvents: hasEvents))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: DesignTokens.Size.calendarCellHeight)
        }
    }

    private func accessibilityLabel(for date: Date, hasEvents: Bool) -> String {
        let base = date.formatted(.dateTime.month().day().weekday(.wide))
        let lunar = CalendarFormatting.lunarCellLabel(for: date)
        return "\(base)，农历\(lunar)" + (hasEvents ? "，有日程" : "")
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

    // MARK: - 当天日程

    private var dayPanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(selectedDate.formatted(date: .complete, time: .omitted))
                    .font(DesignTokens.Typography.panelTitle)
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(service.lunarDateInfo(for: selectedDate))
                    if showWeekNumber {
                        Text("· 第 \(CalendarFormatting.weekNumber(for: selectedDate, calendar: calendar)) 周")
                    }
                }
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.top, DesignTokens.Spacing.xl)

            Divider().opacity(0.3)

            switch service.accessState {
            case .notDetermined: permissionPrompt
            case .denied: deniedPrompt
            case .authorized: eventList
            }
        }
    }

    private var permissionPrompt: some View {
        statePlaceholder(
            icon: "calendar.badge.exclamationmark",
            title: "授权后可在这里查看日程",
            detail: "Quick 只读取日程用于展示和开始前提醒，不会修改或上传。"
        ) {
            Button("授权访问日历") {
                Task { await service.requestAccess() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var deniedPrompt: some View {
        statePlaceholder(
            icon: "lock.shield",
            title: "没有日历访问权限",
            detail: "请在「系统设置 → 隐私与安全性 → 日历」里允许 Quick，回来后会自动刷新。"
        ) {
            Button("打开系统设置") { service.openSystemSettings() }
                .buttonStyle(.borderedProminent)
        }
        .task {
            // 用户在系统设置里改完回到这里：轮询到授权就自动恢复，不用再点任何东西
            while !Task.isCancelled {
                service.refreshAccessState()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func statePlaceholder<Action: View>(
        icon: String, title: String, detail: String, @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(title).font(DesignTokens.Typography.rowTitle)
            Text(detail)
                .font(DesignTokens.Typography.keyCap)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
            action()
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var eventList: some View {
        if events.isEmpty {
            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(DesignTokens.Typography.emptyStateIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(calendar.isDateInToday(selectedDate) ? "今天没有日程安排" : "这一天没有日程安排")
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(events) { event in
                        eventRow(event)
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Circle()
                .fill(color(for: event))
                .frame(width: DesignTokens.Size.calendarDot, height: DesignTokens.Size.calendarDot)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(event.title)
                    .font(DesignTokens.Typography.rowTitle)
                    .lineLimit(2)
                Text(subtitle(for: event))
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if let link = event.meetingLink {
                Button {
                    NSWorkspace.shared.open(link)
                } label: {
                    Label("加入会议", systemImage: "video.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(link.absoluteString)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(for event: CalendarEvent) -> String {
        [event.timeRange, event.location].compactMap { $0 }.joined(separator: " · ")
    }

    private func color(for event: CalendarEvent) -> Color {
        guard let c = event.color else { return DesignTokens.Colors.progress }
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
}
