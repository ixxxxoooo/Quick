// CalendarService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import CoreGraphics
import EventKit
import Foundation
import QuickCore

/// 日历权限状态
enum CalendarAuthorizationState: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

/// 系统日历源信息（供设置页按日历启用/停用，避免与内置节假日重复）
struct CalendarSource: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let colorHex: String
    let isSubscriptionOrHoliday: Bool
}

/// 日历服务
///
/// 封装 EventKit 操作，提供日历权限管理、按日/按区间事件查询与系统日历变更通知。
@MainActor
@Observable
final class CalendarService {

    private let eventStore = EKEventStore()
    private(set) var hasAccess = false
    private(set) var authorizationState: CalendarAuthorizationState = .notDetermined

    /// 系统日历事件库或权限变化时的递增令牌，驱动视图自动重拉当前月份日程
    private(set) var changeToken: Int = 0

    private var storeChangedObserver: NSObjectProtocol?
    private let log = QuickLog.plugin("calendar")

    /// 请求日历访问权限并注册变更监听
    func requestAccess() {
        refreshAuthorizationStatus()
        observeStoreChangesIfNeeded()

        Task {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                hasAccess = granted
                authorizationState = granted ? .authorized : .denied
                changeToken &+= 1
            } catch {
                refreshAuthorizationStatus()
                log.error("请求日历权限失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 同步当前系统日历授权状态（仅在插件激活或用户主动刷新时调用）
    func refreshAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            hasAccess = true
            authorizationState = .authorized
        case .notDetermined:
            hasAccess = false
            authorizationState = .notDetermined
        case .denied, .restricted, .writeOnly:
            hasAccess = false
            authorizationState = .denied
        @unknown default:
            hasAccess = false
            authorizationState = .denied
        }
    }

    /// 获取系统中全部可用的事件日历源
    func availableCalendars() -> [CalendarSource] {
        guard hasAccess else { return [] }
        return eventStore.calendars(for: .event)
            .map { cal in
                let isSub = cal.type == .subscription
                    || cal.title.localizedStandardContains("节假日")
                    || cal.title.localizedStandardContains("Holiday")
                return CalendarSource(
                    id: cal.calendarIdentifier,
                    title: Self.nonEmpty(cal.title) ?? "未命名日历",
                    colorHex: Self.hexColor(from: cal.cgColor),
                    isSubscriptionOrHoliday: isSub
                )
            }
            .sorted { lhs, rhs in
                if lhs.isSubscriptionOrHoliday != rhs.isSubscriptionOrHoliday {
                    return lhs.isSubscriptionOrHoliday && !rhs.isSubscriptionOrHoliday
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    /// 获取今日事件
    func todayEvents() async -> [CalendarEvent] {
        guard hasAccess else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }
        return await events(from: startOfDay, to: endOfDay)
    }

    /// 获取指定日期区间内的全部事件（左闭右开 `[startDate, endDate)`）
    func events(from startDate: Date, to endDate: Date) async -> [CalendarEvent] {
        guard hasAccess, startDate < endDate else { return [] }
        guard PluginDefaults.isEnabled(CalendarPreferences.showSystemEvents, default: true) else {
            return []
        }

        let rawDisabled = UserDefaults.standard.string(forKey: CalendarPreferences.disabledCalendarIDs) ?? ""
        let disabledIDs = CalendarPreferences.disabledIDs(from: rawDisabled)

        let targetCalendars: [EKCalendar]?
        if disabledIDs.isEmpty {
            targetCalendars = nil
        } else {
            let filtered = eventStore.calendars(for: .event).filter {
                !disabledIDs.contains($0.calendarIdentifier)
            }
            // EventKit 中 calendars 传空数组会回退为查询所有日历，因此全部被禁用时直接返回空
            if filtered.isEmpty {
                return []
            }
            targetCalendars = filtered
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: targetCalendars
        )
        let ekEvents = eventStore.events(matching: predicate)

        return CalendarEvent.sortedByStart(
            ekEvents.map { event in
                CalendarEvent(
                    id: Self.stableID(for: event),
                    title: Self.nonEmpty(event.title) ?? "无标题",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarColor: Self.hexColor(from: event.calendar?.cgColor),
                    calendarTitle: event.calendar?.title ?? "",
                    location: Self.nonEmpty(event.location),
                    notes: Self.nonEmpty(event.notes),
                    url: event.url
                )
            }
        )
    }

    /// 获取农历日期信息
    func lunarDateInfo(for date: Date = Date()) -> String {
        CalendarFormatting.lunar(for: date)
    }

    /// 打开系统设置 → 隐私与安全性 → 日历
    func openSystemCalendarPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 打开 macOS 系统「日历.app」
    func openSystemCalendarApp() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        }
    }

    // MARK: - 内部辅助

    private func observeStoreChangesIfNeeded() {
        guard storeChangedObserver == nil else { return }
        storeChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAuthorizationStatus()
                self?.changeToken &+= 1
            }
        }
    }

    /// 生成稳定的事件 ID（兼顾周期性重复事件在不同日期的实例）
    private static func stableID(for event: EKEvent) -> String {
        let base = event.eventIdentifier ?? UUID().uuidString
        let startStamp = Int(event.startDate.timeIntervalSince1970)
        return "\(base)#\(startStamp)"
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// 将 `CGColor` 转为 `#RRGGBB` 字符串，供 Model 层无 UI 依赖存储
    private static func hexColor(from cgColor: CGColor?) -> String {
        guard let cgColor,
            let srgb = cgColor.converted(
                to: CGColorSpace(name: CGColorSpace.sRGB)!,
                intent: .defaultIntent,
                options: nil
            ),
            let components = srgb.components,
            components.count >= 3
        else {
            return ""
        }
        let r = Int((max(0, min(1, components[0])) * 255).rounded())
        let g = Int((max(0, min(1, components[1])) * 255).rounded())
        let b = Int((max(0, min(1, components[2])) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
