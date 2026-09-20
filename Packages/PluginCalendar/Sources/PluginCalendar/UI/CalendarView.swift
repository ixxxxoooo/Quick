// CalendarView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 日历插件视图
struct CalendarView: View {

    let service: CalendarService

    @State private var events: [CalendarService.CalendarEvent] = []
    @State private var selectedDate = Date()

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            // 日期信息
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDate.formatted(date: .complete, time: .omitted))
                        .font(DesignTokens.Typography.panelTitle)
                    Text(service.lunarDateInfo())
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.top, DesignTokens.Spacing.md)

            Divider().opacity(0.3)

            // 今日事件
            if events.isEmpty {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text("今天没有日程安排")
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(events) { event in
                            HStack(spacing: DesignTokens.Spacing.md) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(DesignTokens.Typography.rowTitle)
                                    Text(event.timeRange)
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, DesignTokens.Spacing.xl)
                            .padding(.vertical, DesignTokens.Spacing.md)
                        }
                    }
                }
            }
        }
        .task {
            events = await service.todayEvents()
        }
    }
}
