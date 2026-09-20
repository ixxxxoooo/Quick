// SnippetStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 文本片段存储
///
/// 一个片段一行，增删改各一条语句 —— 旧版每次改动都把整个数组编码成 JSON 重写文件，
/// 写入失败还被 `try?` 静默吞掉，用户会以为片段保存了、其实已经丢了。
///
/// 内存缓存保留给 SwiftUI 直接读，但数据库才是真相：写入失败时缓存回到库里的实际
/// 状态，而不是继续显示一个没落库的假象。
@MainActor
@Observable
final class SnippetStore {

    private(set) var snippets: [Snippet] = []

    private let log = QuickLog.plugin(SnippetsPlugin.id)

    /// 存储句柄
    private let storage: PluginStorage

    /// 初始化并加载
    ///
    /// 同步加载：数据库就在本地，一次查询是微秒级，没有必要把它变成异步再让视图等一轮。
    /// - Parameter storage: 由 AppCore 注入的存储句柄（测试传内存库）
    init(storage: PluginStorage) {
        self.storage = storage
        load()
    }

    // MARK: - 查询

    /// 搜索片段
    func search(_ query: String) -> [Snippet] {
        guard !query.isEmpty else { return snippets }
        let lower = query.lowercased()
        return snippets.filter {
            $0.title.lowercased().contains(lower) || ($0.keyword?.lowercased().contains(lower) ?? false)
                || $0.content.lowercased().contains(lower)
        }
    }

    // MARK: - 增删改

    /// 添加片段
    func add(_ snippet: Snippet) {
        do {
            try storage.database.execute(Self.insertSQL, Self.bindings(snippet))
        } catch {
            log.error("片段写入失败：\(error)")
        }
        reloadCacheFromDatabase()
    }

    /// 更新片段
    func update(_ snippet: Snippet) {
        do {
            try storage.database.execute(
                """
                UPDATE snippets
                SET title = ?, content = ?, keyword = ?, category = ?, updated_at = ?
                WHERE id = ?
                """,
                [
                    .text(snippet.title),
                    .text(snippet.content),
                    snippet.keyword.map { SQLiteValue.text($0) } ?? .null,
                    snippet.category.map { SQLiteValue.text($0) } ?? .null,
                    .date(snippet.updatedAt),
                    .text(snippet.id.uuidString)
                ])
        } catch {
            log.error("片段更新失败：\(error)")
        }
        reloadCacheFromDatabase()
    }

    /// 删除片段
    func remove(_ id: UUID) {
        do {
            try storage.database.execute(
                "DELETE FROM snippets WHERE id = ?", [.text(id.uuidString)])
        } catch {
            log.error("片段删除失败：\(error)")
        }
        reloadCacheFromDatabase()
    }

    // MARK: - 持久化

    /// 从数据库重新读回内存缓存
    func load() {
        do {
            snippets = try Self.fetchAll(from: storage.database)
            log.info("片段已加载，\(self.snippets.count, privacy: .public) 个")
        } catch {
            // 读不出来不能让插件起不来：记一条 error，按空列表继续
            log.error("片段读取失败，已按空列表继续：\(error)")
            snippets = []
        }
    }

    /// 把内存缓存刷成数据库里的真实内容
    ///
    /// 平时的改动已经逐条写过了，这里只是确保退出前界面与库里一致。
    func save() {
        reloadCacheFromDatabase()
    }

    /// 按数据库里的真实内容重排内存缓存
    private func reloadCacheFromDatabase() {
        do {
            snippets = try Self.fetchAll(from: storage.database)
        } catch {
            log.error("片段缓存刷新失败：\(error)")
        }
    }

    // MARK: - SQL 片段

    /// 最新的排在最前；同一时刻创建的按 rowid 定序，避免顺序随查询计划漂移
    private static let selectSQL = """
        SELECT id, title, content, keyword, category, created_at, updated_at
        FROM snippets
        ORDER BY created_at DESC, rowid DESC
        """

    private static let insertSQL = """
        INSERT INTO snippets (id, title, content, keyword, category, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            content = excluded.content,
            keyword = excluded.keyword,
            category = excluded.category,
            updated_at = excluded.updated_at
        """

    private static func bindings(_ snippet: Snippet) -> [SQLiteValue] {
        [
            .text(snippet.id.uuidString),
            .text(snippet.title),
            .text(snippet.content),
            snippet.keyword.map { SQLiteValue.text($0) } ?? .null,
            snippet.category.map { SQLiteValue.text($0) } ?? .null,
            .date(snippet.createdAt),
            .date(snippet.updatedAt)
        ]
    }

    private static func fetchAll(from database: SQLiteDatabase) throws -> [Snippet] {
        try database.query(selectSQL).compactMap(snippet(from:))
    }

    /// 一行 → 一个片段
    private static func snippet(from row: SQLiteRow) -> Snippet? {
        guard let idText = row.text("id"), let id = UUID(uuidString: idText) else { return nil }

        return Snippet(
            id: id,
            title: row.text("title") ?? "",
            content: row.text("content") ?? "",
            keyword: row.text("keyword"),
            category: row.text("category"),
            createdAt: row.date("created_at") ?? Date(),
            updatedAt: row.date("updated_at") ?? Date())
    }
}
