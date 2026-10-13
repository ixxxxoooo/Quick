// HolidayStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Synchronization

/// 法定节假日数据：内置数据 + 本地缓存 + 联网更新
///
/// 数据的优先级是「联网拿到并校验过的 > 内置」，同一年后者被前者整年覆盖。
/// `Mutex` 保护状态，所以它是 `Sendable` 的、`nonisolated` 的搜索路径可以直接读，
/// 不需要新增 actor（见 AGENTS.md）。联网只是锦上添花：任何失败都静默回落到现有数据。
nonisolated final class HolidayStore: Sendable {

    /// 缓存在 `UserDefaults` 里的键。它是缓存而不是用户设置，所以不放进 `PluginSettingKey`
    static let storageKey = "calendar.holidays.cache"
    /// 成功更新后至少隔这么久才再拉：放假安排一年只公布一次，每周看一眼足够及时
    static let successInterval: TimeInterval = 7 * 24 * 3600
    /// 失败后至少隔这么久才重试：网络不通时不要每次打开日历都发请求
    static let failureInterval: TimeInterval = 3600
    /// 按顺序尝试的数据源：jsDelivr 在国内更稳，GitHub 原始地址兜底
    static let endpoints = [
        "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/%d.json",
        "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/%d.json",
    ]

    /// 落盘的缓存：每年一份原始 JSON + 上次成功 / 尝试的时间
    private struct Persisted: Codable {
        var files: [Int: Data] = [:]
        var lastSuccess: Date?
        var lastAttempt: Date?
    }

    private struct State {
        var calendar: HolidayCalendar
        var persisted: Persisted
        var isRefreshing = false
    }

    private let state: Mutex<State>
    private let suiteName: String?
    private let log = QuickLog.plugin("calendar")

    /// - Parameters:
    ///   - suiteName: 缓存存放的 `UserDefaults` 套件；默认标准存储，测试给独立套件
    ///   - bundled: 内置数据，年份 → JSON 文本；测试可注入
    init(suiteName: String? = nil, bundled: [Int: String] = BundledHolidays.json) {
        self.suiteName = suiteName
        let persisted = Self.store(suiteName).data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Persisted.self, from: $0) } ?? Persisted()

        var files = bundled.compactMap { HolidayYearFile.parse(Data($0.value.utf8)) }
        files += persisted.files.values.compactMap(HolidayYearFile.parse)
        state = Mutex(State(calendar: HolidayCalendar(files: files), persisted: persisted))
    }

    private static func store(_ suiteName: String?) -> UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// 当前可用的全部节假日数据
    var calendar: HolidayCalendar {
        state.withLock { $0.calendar }
    }

    /// 上一次成功联网检查的时间；从没成功过为 `nil`
    var lastSuccess: Date? {
        state.withLock { $0.persisted.lastSuccess }
    }

    /// 到点才联网更新当年与次年；`force` 跳过时间间隔（设置页的「立即检查」）
    ///
    /// - Parameters:
    ///   - fetch: 取某一年原始 JSON 的实现，默认走网络；测试注入固定数据
    /// - Returns: 本次是否拿到了至少一份有效的新数据
    @discardableResult
    func refreshIfNeeded(
        now: Date = Date(),
        force: Bool = false,
        fetch: @Sendable (Int) async throws -> Data = { try await HolidayStore.download(year: $0) }
    ) async -> Bool {
        let shouldRun = state.withLock { state -> Bool in
            guard !state.isRefreshing else { return false }
            if !force {
                let persisted = state.persisted
                if let success = persisted.lastSuccess, now.timeIntervalSince(success) < Self.successInterval,
                    now.timeIntervalSince(success) >= 0
                {
                    return false
                }
                if let attempt = persisted.lastAttempt, now.timeIntervalSince(attempt) < Self.failureInterval,
                    now.timeIntervalSince(attempt) >= 0
                {
                    return false
                }
            }
            state.isRefreshing = true
            state.persisted.lastAttempt = now
            return true
        }
        guard shouldRun else { return false }

        let year = CivilDate(now).year
        var fetched: [Int: Data] = [:]
        var reachedServer = false
        for target in [year, year + 1] {
            do {
                let data = try await fetch(target)
                reachedServer = true
                guard let file = HolidayYearFile.parse(data), file.year == target else {
                    // 次年的安排通常要到年底才公布，那时返回的是空数据，不是错误
                    log.info("\(target, privacy: .public) 年节假日数据暂不可用，保留现有数据")
                    continue
                }
                fetched[target] = data
            } catch {
                log.warning("拉取 \(target, privacy: .public) 年节假日失败：\(error.localizedDescription, privacy: .public)")
            }
        }

        state.withLock { state in
            state.isRefreshing = false
            guard reachedServer else { return }
            state.persisted.lastSuccess = now
            for (target, data) in fetched { state.persisted.files[target] = data }
            let bundled = BundledHolidays.json.compactMap { HolidayYearFile.parse(Data($0.value.utf8)) }
            let cached = state.persisted.files.values.compactMap(HolidayYearFile.parse)
            state.calendar = HolidayCalendar(files: bundled + cached)
        }
        persist()
        log.notice("节假日数据已检查，更新 \(fetched.count, privacy: .public) 年")
        return !fetched.isEmpty
    }

    private func persist() {
        let snapshot = state.withLock { $0.persisted }
        guard let encoded = try? JSONEncoder().encode(snapshot) else {
            log.error("节假日缓存编码失败，本次不落盘")
            return
        }
        Self.store(suiteName).set(encoded, forKey: Self.storageKey)
    }

    private static func download(year: Int) async throws -> Data {
        var lastError: Error = URLError(.badURL)
        for template in endpoints {
            guard let url = URL(string: String(format: template, year)) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
