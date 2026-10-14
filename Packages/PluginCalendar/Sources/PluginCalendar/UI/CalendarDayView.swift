// CalendarDayView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// 日视图的时间轴：全天事件置顶，其余按小时刻度摆放，重叠的并排分列
///
/// 布局全部来自 `CalendarDayLayout.timeline`（纯逻辑、有单测），这里只负责把分钟换算成点。
struct CalendarDayTimeline: View {

    let day: Date
    let timeline: CalendarDayLayout.Timeline
    let isToday: Bool

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if !timeline.allDay.isEmpty { allDayStrip }
            hourScroll
        }
    }

    // MARK: - 全天

    private var allDayStrip: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            ForEach(timeline.allDay) { event in
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("全天")
                        .font(DesignTokens.Typography.compactKeyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(event.title)
                        .font(DesignTokens.Typography.keyCap)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(
                    event.displayColor.opacity(DesignTokens.Opacity.tint),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous))
            }
        }
    }

    // MARK: - 小时刻度 + 事件

    private var hourScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourGrid
                    eventBlocks
                    if isToday { nowLine }
                }
                .frame(height: DesignTokens.Size.calendarHourHeight * CGFloat(24))
            }
            // 换天时重新定位：对准第一件事 / 现在，别停在凌晨的空白里
            .task(id: day) {
                let nowMinutes = calendar.component(.hour, from: Date()) * 60
                    + calendar.component(.minute, from: Date())
                let hour = CalendarDayLayout.initialScrollHour(
                    timeline: timeline, isToday: isToday, nowMinute: nowMinutes)
                proxy.scrollTo(hour, anchor: .top)
            }
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                    Text(String(format: "%02d:00", hour))
                        .font(DesignTokens.Typography.compactKeyCap)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(width: DesignTokens.Size.calendarTimelineGutter, alignment: .trailing)
                    Rectangle()
                        .fill(DesignTokens.Colors.cardStroke)
                        .frame(height: DesignTokens.Size.hairline)
                        .padding(.top, DesignTokens.Spacing.sm)
                }
                .frame(height: DesignTokens.Size.calendarHourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private var eventBlocks: some View {
        GeometryReader { proxy in
            let leading = DesignTokens.Size.calendarTimelineGutter + DesignTokens.Spacing.sm
            let available = max(proxy.size.width - leading, 0)
            ForEach(timeline.placed) { placed in
                let columnWidth = available / CGFloat(placed.columnCount)
                let top = CGFloat(placed.startMinute) / 60 * DesignTokens.Size.calendarHourHeight
                let height = CGFloat(placed.endMinute - placed.startMinute) / 60
                    * DesignTokens.Size.calendarHourHeight
                eventBlock(placed.event)
                    .frame(
                        width: max(columnWidth - DesignTokens.Spacing.xxs, 0),
                        height: max(height - DesignTokens.Spacing.xxs, 0), alignment: .topLeading
                    )
                    .offset(x: leading + columnWidth * CGFloat(placed.column), y: top)
            }
        }
    }

    private func eventBlock(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(event.title)
                .font(DesignTokens.Typography.keyCap)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(2)
            Text(event.timeRange)
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            event.displayColor.opacity(DesignTokens.Opacity.tint),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(event.displayColor)
                .frame(width: DesignTokens.Spacing.xxs)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// 「现在」红线：每分钟刷新一次，不为它起额外定时器
    private var nowLine: some View {
        TimelineView(.everyMinute) { context in
            let minutes = calendar.component(.hour, from: context.date) * 60
                + calendar.component(.minute, from: context.date)
            Rectangle()
                .fill(DesignTokens.Colors.destructive)
                .frame(height: DesignTokens.Size.hairline * 2)
                .padding(.leading, DesignTokens.Size.calendarTimelineGutter)
                .offset(y: CGFloat(minutes) / 60 * DesignTokens.Size.calendarHourHeight)
        }
        .allowsHitTesting(false)
    }
}
