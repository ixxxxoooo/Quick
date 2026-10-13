// CalendarEventsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickUI
import SwiftUI

/// 所选日期的日程区：授权引导 / 空状态 / 事件列表
///
/// 三种状态都是**紧凑的一块**，不再各自撑满整个右栏 —— 撑满只会在没有日程时留下一大片空白。
struct CalendarEventsView: View {

    let service: CalendarService
    let events: [CalendarEvent]
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Label("日程", systemImage: "calendar")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            switch service.accessState {
            case .notDetermined: permissionPrompt
            case .denied: deniedPrompt
            case .authorized: eventList
            }
        }
    }

    // MARK: - 授权引导

    private var permissionPrompt: some View {
        notice(
            icon: "calendar.badge.exclamationmark",
            title: "授权后可在这里查看日程",
            detail: "Quick 只读取日程用于展示和开始前提醒，不会修改或上传。"
        ) {
            Button("授权访问日历") {
                Task { await service.requestAccess() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var deniedPrompt: some View {
        notice(
            icon: "lock.shield",
            title: "没有日历访问权限",
            detail: "请在「系统设置 → 隐私与安全性 → 日历」里允许 Quick，回来后会自动刷新。"
        ) {
            Button("打开系统设置") { service.openSystemSettings() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .task {
            // 用户在系统设置里改完回到这里：轮询到授权就自动恢复，不用再点任何东西
            while !Task.isCancelled {
                service.refreshAccessState()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func notice<Action: View>(
        icon: String, title: String, detail: String, @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.xl) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.iconGlyph)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text(title).font(DesignTokens.Typography.rowTitle)
                Text(detail)
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                action()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    // MARK: - 事件列表

    @ViewBuilder
    private var eventList: some View {
        if events.isEmpty {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(DesignTokens.Typography.iconGlyph)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(isToday ? "今天没有日程安排" : "这一天没有日程安排")
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .padding(.vertical, DesignTokens.Spacing.sm)
        } else {
            LazyVStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(events) { event in
                    eventRow(event)
                }
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
        .padding(.vertical, DesignTokens.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(for event: CalendarEvent) -> String {
        [event.timeRange, event.location].compactMap { $0 }.joined(separator: " · ")
    }

    private func color(for event: CalendarEvent) -> Color {
        guard let c = event.color else { return DesignTokens.Colors.progress }
        return Color(red: c.red, green: c.green, blue: c.blue)  // ui-literal-ok: 日历自带的用户颜色，不是设计值
    }
}
