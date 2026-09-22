// CalcHistoryStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 计算历史存储
///
/// 每次求值提交（回车）时落一条记录，按时间倒序读回。同一个表达式再算一次不新增，
/// 而是把它提到最前并刷新结果 —— 计算稿纸上重复写同一行没有意义。
///
/// ## 为什么用真表而不是键值层
///
/// 历史要排序、要按上限剪枝、要按表达式去重。键值层每次读写都要把整个数组编解码一遍，
/// 条目一多就是全量重写；一张表让这三件事都变成一条 SQL，代价与历史长度无关。
@MainActor
@Observable
final class CalcHistoryStore {

    /// 全部历史（按时间倒序）
    private(set) var entries: [CalcHistoryEntry] = []

    private let log = QuickLog.plugin(CalculatorPlugin.id)

    /// 存储句柄
    private let storage: PluginStorage

    /// 历史条数上限
    ///
    /// 只影响展示与查询成本，不设也跑得动；给它一个上限是为了让「用了几年之后」
    /// 的历史仍然是一个能一眼扫完的列表，而不是无限增长的表。
    static let maxEntries = 200

    /// 初始化并加载历史
    /// - Parameter storage: 由 AppCore 注入的存储句柄（测试传内存库）
    init(storage: PluginStorage) {
        self.storage = storage
        load()
    }

    // MARK: - 写入

    /// 记录一次计算
    ///
    /// 去重、插入、剪枝在同一次事务里完成：崩在中间不会留下「超限的历史」或
    /// 「删了旧的却没插新的」。
    /// - Parameters:
    ///   - expression: 用户输入的表达式原文
    ///   - result: 格式化后的结果
    func record(expression: String, result: String) {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let statements = [
            SQLiteStatement(
                "DELETE FROM calc_history WHERE expression = ?", [.text(trimmed)]),
            SQLiteStatement(
                """
                INSERT INTO calc_history (id, expression, result, created_at)
                VALUES (?, ?, ?, ?)
                """,
                [.text(UUID().uuidString), .text(trimmed), .text(result), .date(Date())]),
            Self.pruneStatement
        ]

        do {
            try storage.database.transaction(statements)
        } catch {
            log.error("计算历史写入失败：\(error)")
            return
        }
        reloadCache()
    }

    /// 删除一条历史
    /// - Parameter id: 条目 ID
    func remove(_ id: UUID) {
        do {
            try storage.database.execute(
                "DELETE FROM calc_history WHERE id = ?", [.text(id.uuidString)])
        } catch {
            log.error("计算历史删除失败：\(error)")
        }
        reloadCache()
    }

    /// 清空全部历史
    func clear() {
        do {
            try storage.database.execute("DELETE FROM calc_history")
        } catch {
            log.error("计算历史清空失败：\(error)")
        }
        reloadCache()
    }

    // MARK: - 持久化

    /// 从数据库读回内存缓存
    func load() {
        do {
            entries = try Self.fetchAll(from: storage.database)
            log.info("计算历史已加载，\(self.entries.count, privacy: .public) 条")
        } catch {
            // 读不出来不能让插件起不来：记一条 error，按空历史继续
            log.error("计算历史读取失败，已按空历史继续：\(error)")
            entries = []
        }
    }

    /// 把内存缓存刷成数据库里的真实内容
    func save() {
        reloadCache()
    }

    private func reloadCache() {
        do {
            entries = try Self.fetchAll(from: storage.database)
        } catch {
            log.error("计算历史缓存刷新失败：\(error)")
        }
    }

    // MARK: - SQL 片段

    /// `rowid` 是次序的最终判据：同一毫秒内提交的两条记录时间戳可能完全相等，
    /// 只按时间排序会让它们的相对顺序随查询计划变化。
    private static let selectSQL = """
        SELECT id, expression, result, created_at
        FROM calc_history
        ORDER BY created_at DESC, rowid DESC
        """

    /// 条数剪枝：只保留最新 `maxEntries` 条
    private static var pruneStatement: SQLiteStatement {
        SQLiteStatement(
            """
            DELETE FROM calc_history
            WHERE id NOT IN (
                SELECT id FROM calc_history ORDER BY created_at DESC, rowid DESC LIMIT ?
            )
            """,
            [.int(maxEntries)])
    }

    private static func fetchAll(from database: SQLiteDatabase) throws -> [CalcHistoryEntry] {
        try database.query(selectSQL).compactMap { row in
            guard let idText = row.text("id"), let id = UUID(uuidString: idText),
                let expression = row.text("expression"), let result = row.text("result")
            else { return nil }
            return CalcHistoryEntry(
                id: id,
                expression: expression,
                result: result,
                timestamp: row.date("created_at") ?? Date())
        }
    }
}
