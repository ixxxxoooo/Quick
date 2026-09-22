// UsageHistory.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 最近使用过的结果
///
/// ## 为什么放在宿主层，而不是某个插件里
///
/// 「最近用过什么」是**跨插件**的事实：用户可能刚用过一个开发工具、再打开一个应用、
/// 又用了翻译。如果每个插件各记各的，宿主就没法回答「按最近使用排序」这个问题 ——
/// 而首屏要的正是这个顺序。
///
/// 键是 `SearchableItem.id`（插件内唯一），所以应用、命令、工具条目都在同一张表里，
/// 排序时天然可比。
///
/// ## 与 `RankingStore` 的分工
///
/// `RankingStore`（启动器插件）记的是「启动次数」，用于给搜索结果加权 ——
/// 次数多说明常用，与时间无关。这里记的是「最后一次用是什么时候」，用于首屏排序 ——
/// 昨天用了 20 次的东西，今天不该排在刚刚用过的前面。
public struct UsageHistory: Sendable {

    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    /// 记录一次使用
    ///
    /// 同一个 id 重复使用只更新时间，不累加计数 —— 这张表的语义是「最近」。
    public func record(itemID: String, at date: Date = Date()) {
        do {
            try database.execute(
                """
                INSERT INTO usage_history (item_id, last_used)
                VALUES (?, ?)
                ON CONFLICT(item_id) DO UPDATE SET last_used = excluded.last_used
                """,
                [.text(itemID), .date(date)])
        } catch {
            // 记不上只影响首屏顺序，不该打断用户正在做的事
            QuickLog.persistence.warning("使用历史写入失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 最近使用过的 id，最新的在前
    ///
    /// - Parameter limit: 最多返回多少条
    /// - Returns: 按 `last_used` 降序的 id；没记录过时返回空数组
    public func recentItemIDs(limit: Int) -> [String] {
        do {
            return try database.query(
                """
                SELECT item_id FROM usage_history
                ORDER BY last_used DESC
                LIMIT ?
                """,
                [.int(limit)]
            ).compactMap { $0.text("item_id") }
        } catch {
            QuickLog.persistence.error(
                "使用历史读取失败，首屏按默认顺序显示：\(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    /// 某个 id 最近一次使用的时间（测试与排查用）
    public func lastUsed(itemID: String) -> Date? {
        do {
            return try database.query(
                "SELECT last_used FROM usage_history WHERE item_id = ?",
                [.text(itemID)]
            ).first?.date("last_used")
        } catch {
            QuickLog.persistence.error(
                "使用历史读取失败：\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// 清空历史（「重置最近使用」这类动作）
    public func removeAll() {
        do {
            try database.execute("DELETE FROM usage_history")
        } catch {
            QuickLog.persistence.error(
                "使用历史清空失败：\(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

// MARK: - 宿主的迁移

public extension SQLiteMigration {

    /// 宿主自己那份 schema：最近使用
    ///
    /// 与 `core.plugin_data` 并列，都属于宿主：一个放插件的零散状态，一个放跨插件的使用顺序。
    static var coreUsageHistory: SQLiteMigration {
        SQLiteMigration(
            id: "core.usage_history",
            statements: [
                """
                CREATE TABLE IF NOT EXISTS usage_history (
                    item_id TEXT PRIMARY KEY,
                    last_used REAL NOT NULL
                )
                """,
                "CREATE INDEX IF NOT EXISTS idx_usage_last_used ON usage_history(last_used DESC)"
            ])
    }
}
