// CalendarService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import EventKit
import Foundation
import QuickCore
import UserNotifications

/// 日历服务
///
/// 封装 EventKit：权限、按天 / 按月查询、开始前提醒。
/// **不在启动时弹权限框**：授权由用户在日历视图里主动触发；已授权的用户启动后自动开始提醒。
@MainActor
@Observable
final class CalendarService {

    /// 日历访问权限状态
    enum AccessState: Equatable, Sendable {
        case notDetermined
        case authorized
        /// 被拒绝、受限，或只授予了「仅写入」—— 读不到日程，都按这个处理
        case denied
    }

    private let eventStore = EKEventStore()
    private let log = QuickLog.plugin("calendar")

    private(set) var accessState: AccessState

    /// 提醒的通知标识前缀：重排时只清自己的，不动别的通知
    private static let reminderPrefix = "calendar.reminder."
    /// 一次向前排多远的提醒（再远的等下一轮刷新）
    private static let reminderHorizon: TimeInterval = 24 * 3600
    /// 提醒的周期性刷新间隔：跨天运行时保证窗口不会过期
    private static let reminderRefreshInterval: Duration = .seconds(30 * 60)

    private var reminderLoop: Task<Void, Never>?
    private var storeObserver: Task<Void, Never>?
    private var defaultsObserver: Task<Void, Never>?
    /// 上一次排提醒时用的提前量：偏好变了才需要重排
    private var scheduledLead: Int?

    /// - Parameter accessState: 仅测试注入；生产路径读系统的真实授权状态
    init(accessState: AccessState? = nil) {
        self.accessState = accessState ?? Self.currentAccessState()
    }

    // MARK: - 权限

    private static func currentAccessState() -> AccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
        case .restricted, .denied, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    /// 向系统申请完整日历访问；结果同步到 `accessState`
    @discardableResult
    func requestAccess() async -> AccessState {
        do {
            _ = try await eventStore.requestFullAccessToEvents()
        } catch {
            log.error("请求日历权限失败: \(error.localizedDescription, privacy: .public)")
        }
        accessState = Self.currentAccessState()
        log.notice("日历权限状态：\(String(describing: self.accessState), privacy: .public)")
        if accessState == .authorized { startReminders() }
        return accessState
    }

    /// 从系统设置回来后重新读取权限（用户可能在那里改过）
    func refreshAccessState() {
        let latest = Self.currentAccessState()
        guard latest != accessState else { return }
        accessState = latest
        if latest == .authorized { startReminders() } else { stopReminders() }
    }

    /// 打开系统设置的「隐私 → 日历」
    func openSystemSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 查询

    /// 某一天的事件（按开始时间排序）；未授权返回空
    func events(on day: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events(from: start, to: end)
    }

    /// 一段时间内的事件（按开始时间排序）；未授权返回空
    ///
    /// 周视图一次取一周再按天归并，而不是逐日各查一次 EventKit。
    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard accessState == .authorized, start < end else { return [] }
        return fetch(from: start, to: end)
    }

    /// 今日事件
    func todayEvents() async -> [CalendarEvent] {
        events(on: Date())
    }

    /// 某月里有事件的日子（每天零点），用来在月历上画小圆点
    func daysWithEvents(inMonthOf month: Date, calendar: Calendar = .current) -> Set<Date> {
        guard accessState == .authorized, let interval = calendar.dateInterval(of: .month, for: month)
        else { return [] }
        var days = Set<Date>()
        for event in fetch(from: interval.start, to: interval.end) {
            // 跨天事件在每一天都标点；最多遍历到月底，避免超长事件拖慢
            var cursor = calendar.startOfDay(for: max(event.startDate, interval.start))
            let last = min(event.endDate, interval.end)
            repeat {
                days.insert(cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            } while cursor < last
        }
        return days
    }

    private func fetch(from start: Date, to end: Date) -> [CalendarEvent] {
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let extract = CalendarPreferences.extractsMeetingLinks()
        return CalendarEvent.sortedByStart(
            eventStore.events(matching: predicate).map { Self.translate($0, extractLinks: extract) })
    }

    /// `EKEvent` → 纯值事件，全仓唯一的翻译点
    private static func translate(_ event: EKEvent, extractLinks: Bool) -> CalendarEvent {
        let link = extractLinks
            ? MeetingLinkExtractor.firstLink(in: [event.url?.absoluteString, event.location, event.notes, event.title])
            : nil
        return CalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "无标题",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            color: event.calendar.flatMap { color(of: $0) },
            location: event.location.flatMap { $0.isEmpty ? nil : $0 },
            meetingLink: link)
    }

    private static func color(of calendar: EKCalendar) -> CalendarColor? {
        guard let rgb = calendar.color?.usingColorSpace(.sRGB) else { return nil }
        return CalendarColor(
            red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
    }

    // MARK: - 提醒

    /// 开始排提醒并保持更新；可重复调用
    func startReminders() {
        guard accessState == .authorized else { return }
        if reminderLoop == nil {
            reminderLoop = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.rescheduleReminders()
                    try? await Task.sleep(for: Self.reminderRefreshInterval)
                }
            }
        }
        if storeObserver == nil {
            // 用户在系统日历里改了日程，提醒要跟着改
            storeObserver = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                    await self?.rescheduleReminders()
                }
            }
        }
        if defaultsObserver == nil {
            // 设置页改了提前量，不必等下一个刷新周期
            defaultsObserver = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                    guard let self else { return }
                    if scheduledLead != CalendarPreferences.reminderMinutes() {
                        await rescheduleReminders()
                    }
                }
            }
        }
        log.notice("日程提醒已启动")
    }

    /// 停止提醒并清掉已排的通知
    func stopReminders() {
        reminderLoop?.cancel()
        storeObserver?.cancel()
        defaultsObserver?.cancel()
        reminderLoop = nil
        storeObserver = nil
        defaultsObserver = nil
        scheduledLead = nil
        guard Bundle.main.bundleIdentifier != nil else { return }
        Task { await Self.clearPendingReminders() }
        log.notice("日程提醒已停止")
    }

    /// 清掉旧的、按当前日程重排
    private func rescheduleReminders() async {
        // 单元测试进程没有 bundle，`UNUserNotificationCenter` 会直接崩溃
        guard Bundle.main.bundleIdentifier != nil, accessState == .authorized else { return }
        let lead = CalendarPreferences.reminderMinutes()
        scheduledLead = lead
        await Self.clearPendingReminders()
        guard lead > 0 else { return }

        let now = Date()
        let events = fetch(from: now, to: now.addingTimeInterval(Self.reminderHorizon + TimeInterval(lead * 60)))
        let plan = ReminderPlanner.plan(events: events, now: now, leadMinutes: lead)
            .filter { $0.fireDate < now.addingTimeInterval(Self.reminderHorizon) }
        guard !plan.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        // 只在确实有提醒要发时才申请通知权限，不在启动时无故打扰
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            log.notice("通知权限未授予，跳过 \(plan.count) 条日程提醒")
            return
        }
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = Self.notificationBody(for: reminder)
            content.sound = .default
            let interval = max(1, reminder.fireDate.timeIntervalSinceNow)
            let request = UNNotificationRequest(
                identifier: Self.reminderPrefix + reminder.eventID + "." + String(Int(reminder.fireDate.timeIntervalSince1970)),
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
            do {
                try await center.add(request)
            } catch {
                log.error("添加提醒失败: \(error.localizedDescription, privacy: .public)")
            }
        }
        log.notice("已排 \(plan.count) 条日程提醒（提前 \(lead) 分钟）")
    }

    private static func clearPendingReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(reminderPrefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func notificationBody(for reminder: ReminderPlanner.Reminder) -> String {
        var parts = ["\(reminder.leadMinutes) 分钟后开始", reminder.event.timeRange]
        if let location = reminder.event.location { parts.append(location) }
        if let link = reminder.event.meetingLink { parts.append(link.absoluteString) }
        return parts.joined(separator: " · ")
    }
}
