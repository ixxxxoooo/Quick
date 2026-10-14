// CalendarInfoViews.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// 卡片底：与设置页、剪贴板预览共用的填充 + 描边
struct CalendarCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                DesignTokens.Colors.cardFill,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: DesignTokens.Size.hairline)
            }
    }
}

extension View {
    func calendarCard() -> some View { modifier(CalendarCardBackground()) }
}

/// 一枚小标签：节日名、节气、放假 / 补班状态
private struct DayTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(DesignTokens.Typography.keyCap)
            .foregroundStyle(tint)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(tint.opacity(DesignTokens.Opacity.tint), in: Capsule())
            .fixedSize()
    }
}

/// 所选日期的信息卡：大号日期 + 公历 / 农历 / 干支 / 节日 / 放假状态
struct DayInfoCard: View {

    let date: Date
    let day: AlmanacDay
    let status: HolidayStatus?
    let weekNumber: Int?
    let showAlmanac: Bool

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.xl) {
            VStack(spacing: DesignTokens.Spacing.xxs) {
                Text("\(day.date.day)")
                    .font(DesignTokens.Typography.calendarHeroDay)
                    .monospacedDigit()
                Text(date.formatted(.dateTime.weekday(.wide)))
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .frame(width: DesignTokens.Size.calendarHeroColumn)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(date.formatted(.dateTime.year().month(.wide).day()))
                    .font(DesignTokens.Typography.panelTitle)
                Text(secondaryLine)
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                if showAlmanac {
                    Text(ganzhiLine)
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                if !tags.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        ForEach(tags, id: \.text) { tag in
                            DayTag(text: tag.text, tint: tag.tint)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.xl)
        .calendarCard()
        .accessibilityElement(children: .combine)
    }

    private var secondaryLine: String {
        var parts = ["农历 \(day.lunarText)"]
        if let weekNumber { parts.append("第 \(weekNumber) 周") }
        return parts.joined(separator: " · ")
    }

    private var ganzhiLine: String {
        "\(day.ganzhiText) · 属\(day.zodiac)"
    }

    private var tags: [(text: String, tint: Color)] {
        var result: [(String, Color)] = []
        if showAlmanac {
            result += day.festivals.map { ($0, DesignTokens.Colors.destructive) }
            if let term = day.solarTerm { result.append((term, DesignTokens.Colors.progress)) }
        }
        if let status {
            result.append((status.detailText, status.isOffDay ? DesignTokens.Colors.success : DesignTokens.Colors.warning))
        }
        return result
    }
}

/// 近期节假日：名称、日期范围、倒数、补班
struct UpcomingHolidaysCard: View {

    let periods: [HolidayPeriod]
    let today: CivilDate

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Label("近期节假日", systemImage: "calendar.badge.clock")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            if periods.isEmpty {
                Text("暂未公布后续的放假安排。国务院通常在每年 11 月前后发布次年的安排，公布后会自动更新。")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            ForEach(periods, id: \.start) { period in
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(period.name).font(DesignTokens.Typography.rowTitle)
                        Text(detail(of: period))
                            .font(DesignTokens.Typography.keyCap)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Text(period.countdownText(from: today))
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(
                            period.dayNumber(of: today) == nil
                                ? DesignTokens.Colors.textSecondary : DesignTokens.Colors.success)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calendarCard()
    }

    private func detail(of period: HolidayPeriod) -> String {
        [period.rangeText + " · 共 \(period.dayCount) 天", period.makeupText].compactMap { $0 }.joined(separator: " · ")
    }
}

/// 近期节日与节气：官方放假安排公布之前（或之外）右栏的补位内容
struct UpcomingObservancesCard: View {

    let observances: [Almanac.Observance]
    let today: CivilDate

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Label("近期节日", systemImage: "sparkles")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            ForEach(observances, id: \.date) { item in
                HStack(spacing: DesignTokens.Spacing.md) {
                    Text(item.name).font(DesignTokens.Typography.rowTitle)
                    Text(item.date.monthDayText)
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Spacer(minLength: 0)
                    Text(item.countdownText(from: today))
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calendarCard()
    }
}

/// 月历下方的假期倒数条 + 本月假期：把月历下面本来空着的地方利用起来
struct MonthHolidaySummary: View {

    let next: HolidayPeriod?
    let monthPeriods: [HolidayPeriod]
    let today: CivilDate

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if let next {
                Label(next.headline(from: today), systemImage: "party.popper")
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            ForEach(monthPeriods, id: \.start) { period in
                HStack(spacing: DesignTokens.Spacing.md) {
                    Text(period.rangeText)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text(period.name)
                    Spacer(minLength: 0)
                    Text("\(period.dayCount) 天")
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .font(DesignTokens.Typography.keyCap)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calendarCard()
    }
}
