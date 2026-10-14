// AlmanacCache.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Synchronization

/// 黄历结果缓存：按 `CivilDate` 记住 `Almanac.day(for:)` 的产出
///
/// 月历每次重绘要给 28–42 个格子各算一遍农历 / 干支 / 节气，而同一天的结果永远不变。
/// 容量到顶就整体清空：一个月最多 42 天、切几个月就够用，不值得写 LRU。
/// `Mutex` 保护，视图（主 actor）与后台都能直接读。
final class AlmanacCache: Sendable {

    static let shared = AlmanacCache()

    /// 缓存上限（约 2 年的天数，足够来回翻月）
    static let capacity = 800

    private let storage = Mutex<[CivilDate: AlmanacDay]>([:])

    /// 计算次数（仅测试观察「第二次是否命中缓存」）
    private let computations = Mutex(0)

    init() {}

    func day(for date: CivilDate) -> AlmanacDay {
        if let hit = storage.withLock({ $0[date] }) { return hit }
        let value = Almanac.day(for: date)
        computations.withLock { $0 += 1 }
        storage.withLock { cache in
            if cache.count >= Self.capacity { cache.removeAll(keepingCapacity: true) }
            cache[date] = value
        }
        return value
    }

    var computationCount: Int { computations.withLock { $0 } }
    var count: Int { storage.withLock { $0.count } }
}
