// CurrencyRateCache.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Synchronization

/// 汇率缓存：内存里一份、`UserDefaults` 里一份（离线与重启后仍可用）
///
/// `Mutex` 保护状态，所以它是 `Sendable` 的、可以被 `nonisolated` 的搜索路径直接读，
/// 不需要新增 actor（见 AGENTS.md）。
nonisolated final class CurrencyRateCache: Sendable {

    /// 缓存在 `UserDefaults` 里的键。它是缓存而不是用户设置，所以不放进 `PluginSettingKey`
    static let storageKey = "calculator.currencyRates.cache"
    /// 超过这个时长才重新拉：汇率源一天只更新一次，更勤只是白白打扰第三方
    static let maxAge: TimeInterval = 12 * 3600
    static let endpoint = "https://open.er-api.com/v6/latest/USD"

    private let state: Mutex<CurrencyRates?>
    /// 存储套件名（`nil` = 标准存储）。`UserDefaults` 本身不是 `Sendable`，所以只持有名字，用的时候现取
    private let suiteName: String?
    private let log = QuickLog.plugin("calculator")

    /// - Parameters:
    ///   - suiteName: 缓存存放的 `UserDefaults` 套件；默认标准存储，测试给独立套件
    ///   - seed: 测试直接给定的汇率；给了就不读存储
    init(suiteName: String? = nil, seed: CurrencyRates? = nil) {
        self.suiteName = suiteName
        let initial = seed ?? Self.store(suiteName).data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(CurrencyRates.self, from: $0) }
        state = Mutex(initial)
    }

    private static func store(_ suiteName: String?) -> UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// 当前汇率（可能为空：从没拉成功过）
    var current: CurrencyRates? {
        state.withLock { $0 }
    }

    /// 缓存过期（或没有）才联网刷新；失败保留旧缓存
    ///
    /// - Parameter fetch: 取数据的实现，默认走网络；测试注入固定数据
    func refreshIfNeeded(
        now: Date = Date(),
        fetch: @Sendable () async throws -> Data = { try await CurrencyRateCache.download() }
    ) async {
        if let rates = current, now.timeIntervalSince(rates.updatedAt) < Self.maxAge,
            now.timeIntervalSince(rates.updatedAt) >= 0
        {
            return
        }
        do {
            let data = try await fetch()
            guard let fresh = CurrencyRates.parse(data) else {
                log.error("汇率响应无法解析，保留旧缓存")
                return
            }
            state.withLock { $0 = fresh }
            if let encoded = try? JSONEncoder().encode(fresh) {
                Self.store(suiteName).set(encoded, forKey: Self.storageKey)
            }
            log.notice("汇率已更新，\(fresh.perUSD.count, privacy: .public) 个币种")
        } catch {
            log.error("拉取汇率失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func download() async throws -> Data {
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
