// RankingStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 使用频率排序存储
///
/// 记录每个应用的使用次数，用于搜索结果排序。
///
/// ## 为什么从「整份重写」改成「单行自增」
///
/// 旧版每次启动一个应用，都要把整个 `[bundleID: count]` 编码成 JSON 重写文件，
/// 而且带 5 秒防抖 —— 防抖窗口内退出，这一次计数就丢了。现在每行一个应用，
/// 启动一次就是一行 `count + 1`，代价与记录数无关，也不需要防抖。
@MainActor
final class RankingStore {

    /// 使用次数记录（bundleID → 使用次数）
    private var usageCounts: [String: Int] = [:]

    /// 最大使用次数（用于归一化评分）
    private var maxCount: Int = 1

    private let log = QuickLog.plugin(LauncherPlugin.id)

    /// 存储句柄
    private let storage: PluginStorage

    /// 初始化并加载
    /// - Parameter storage: 由 AppCore 注入的存储句柄（测试传内存库）
    init(storage: PluginStorage) {
        self.storage = storage
        load()
    }

    /// 记录一次使用
    /// - Parameter bundleID: 应用 Bundle ID
    func recordUsage(_ bundleID: String) {
        do {
            // 单行 upsert：冲突时 count 自增，不再重写整份数据
            try storage.database.execute(
                """
                INSERT INTO usage_stats (item_id, count, last_used)
                VALUES (?, 1, ?)
                ON CONFLICT(item_id) DO UPDATE SET
                    count = count + 1,
                    last_used = excluded.last_used
                """,
                [.text(bundleID), .date(Date())])
        } catch {
            log.error("使用频率写入失败：\(error)")
            // 写失败就按库里的真相回退，避免内存里出现一个没落库的计数
            load()
            return
        }

        let count = (usageCounts[bundleID] ?? 0) + 1
        usageCounts[bundleID] = count
        if count > maxCount { maxCount = count }
    }

    /// 获取应用的排序评分（0.0 ~ 1.0）
    /// - Parameter bundleID: 应用 Bundle ID
    /// - Returns: 归一化的使用频率评分
    func score(for bundleID: String) -> Double {
        guard let count = usageCounts[bundleID], maxCount > 0 else { return 0 }
        return Double(count) / Double(maxCount)
    }

    // MARK: - 持久化

    /// 从数据库加载
    func load() {
        do {
            let rows = try storage.database.query("SELECT item_id, count FROM usage_stats")
            var counts: [String: Int] = [:]
            for row in rows {
                guard let itemID = row.text("item_id") else { continue }
                counts[itemID] = Int(row.int("count") ?? 0)
            }
            usageCounts = counts
            maxCount = max(counts.values.max() ?? 1, 1)
            log.info("使用频率已加载，\(counts.count, privacy: .public) 个应用")
        } catch {
            log.error("使用频率读取失败，已按空记录继续：\(error)")
            usageCounts = [:]
            maxCount = 1
        }
    }

    /// 把内存缓存刷成数据库里的真实内容
    ///
    /// 每次 `recordUsage` 都已经落库了，这里只是退出前的「确保一致」。
    func save() {
        load()
    }
}
