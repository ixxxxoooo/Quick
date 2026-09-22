// ClipboardStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 剪贴板历史存储
///
/// 管理剪贴板历史条目的内存缓存和数据库持久化。按设置去重、限制条目数量与图片占用。
/// 三个开关（去重、条数上限、图片预算）都在用到的那一刻读设置页的键，不缓存。
///
/// ## 为什么每次改动都直接落库，而没有防抖
///
/// 以前整份历史是一个 JSON 文件，写一次就是重写全文，所以必须防抖 2 秒攒批。
/// 现在每条记录一行，`add` 只插一行、删几行，代价与历史长度无关 —— 防抖失去意义，
/// 反而会让「复制完立刻崩溃」丢掉刚复制的内容。
///
/// ## 上限为什么有两条
///
/// 只按条数限制挡不住图片：500 条 2MB 的截图就是 1GB。所以同时限制图片总字节数，
/// 两者都在同一次事务里剪枝。置顶与收藏的条目永远不参与剪枝。
@MainActor
@Observable
final class ClipboardStore {

    /// 所有条目（按置顶、时间倒序）
    private(set) var entries: [ClipboardEntry] = []

    private let log = QuickLog.plugin(ClipboardPlugin.id)

    /// 存储句柄
    private let storage: PluginStorage

    /// 初始化并加载历史
    ///
    /// 同步加载：数据库就在本地，一次查询是微秒级，没有必要把它变成异步再让视图等一轮。
    /// - Parameter storage: 由 AppCore 注入的存储句柄（测试传内存库）
    init(storage: PluginStorage) {
        self.storage = storage
        load()
    }

    // MARK: - 上限

    /// 最大保存条目数
    ///
    /// 读的是设置页里那个键 —— 以前这里硬编码 500，设置页上的「历史记录上限」
    /// 改了没有任何效果。
    private var maxEntries: Int {
        let configured = UserDefaults.standard.integer(forKey: PluginSettingKey.Clipboard.maxEntries)
        return configured > 0 ? configured : 500
    }

    /// 图片总占用上限
    private var imageByteBudget: Int {
        let configured = UserDefaults.standard.integer(forKey: PluginSettingKey.Clipboard.imageByteBudget)
        return configured > 0 ? configured : 256 * 1024 * 1024
    }

    // MARK: - 增删改

    /// 添加新条目
    ///
    /// 去重、插入、剪枝在同一次事务里完成：任何一步失败都不会留下「超限的历史」
    /// 或「插了一半」的状态。
    /// - Parameter entry: 剪贴板条目
    func add(_ entry: ClipboardEntry) {
        let deduplicates = PluginDefaults.isEnabled(PluginSettingKey.Clipboard.deduplication, default: true)

        // 去重：相同内容不重复记录（图片按数据内容，文本按文本）
        if deduplicates {
            if entry.type == .image {
                entries.removeAll { $0.type == .image && $0.imageData == entry.imageData }
            } else {
                entries.removeAll { $0.text == entry.text }
            }
        }
        entries.insert(entry, at: 0)

        // 语句顺序是有意义的：**先删重复，再插入，最后剪枝**。
        // 反过来的话，去重那一步会把刚插进去的这条按「相同文本」删掉 ——
        // 表现是「复制了但历史里没有」，而且没有任何报错。
        var statements: [SQLiteStatement] = []
        if deduplicates {
            if entry.type == .image {
                statements.append(Self.deleteDuplicateImageStatement(for: entry.imageData ?? Data()))
            } else {
                statements.append(Self.deleteDuplicateTextStatement(for: entry.text))
            }
        }
        statements.append(Self.insertStatement(for: entry))
        statements.append(contentsOf: ClipboardStore.pruneStatements(maxEntries: maxEntries))

        do {
            try storage.database.transaction(statements)
        } catch {
            log.error("剪贴板写入失败：\(error)")
            return
        }
        pruneImageBudget()
        reloadCacheFromDatabase()
    }

    /// 删除条目
    /// - Parameter id: 条目 ID
    func remove(_ id: UUID) {
        do {
            try storage.database.execute(
                "DELETE FROM clipboard_history WHERE id = ?", [.text(id.uuidString)])
        } catch {
            log.error("删除剪贴板条目失败：\(error)")
        }
        reloadCacheFromDatabase()
    }

    /// 清空所有历史（保留收藏和置顶）
    func clearHistory() {
        do {
            try storage.database.execute(
                "DELETE FROM clipboard_history WHERE is_favorite = 0 AND is_pinned = 0")
        } catch {
            log.error("清空剪贴板历史失败：\(error)")
        }
        reloadCacheFromDatabase()
    }

    /// 切换收藏状态
    /// - Parameter id: 条目 ID
    func toggleFavorite(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let isFavorite = !entries[index].isFavorite
        do {
            try storage.database.execute(
                "UPDATE clipboard_history SET is_favorite = ? WHERE id = ?",
                [.bool(isFavorite), .text(id.uuidString)])
        } catch {
            log.error("更新收藏状态失败：\(error)")
        }
        reloadCacheFromDatabase()
    }

    /// 切换置顶状态
    /// - Parameter id: 条目 ID
    func togglePinned(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let isPinned = !entries[index].isPinned
        do {
            try storage.database.execute(
                "UPDATE clipboard_history SET is_pinned = ? WHERE id = ?",
                [.bool(isPinned), .text(id.uuidString)])
        } catch {
            log.error("更新置顶状态失败：\(error)")
        }
        // 置顶会改变排序，而排序由 SQL 的 ORDER BY 定义 —— 内存里自己算顺序
        // 迟早会和库里的不一致，所以改完就重读
        reloadCacheFromDatabase()
    }

    // MARK: - 查询

    /// 收藏的条目
    var favorites: [ClipboardEntry] {
        entries.filter(\.isFavorite)
    }

    /// 按类型筛选
    func entries(ofType type: ClipboardEntry.ContentType) -> [ClipboardEntry] {
        entries.filter { $0.type == type }
    }

    /// 图片条目
    var imageEntries: [ClipboardEntry] {
        entries.filter { $0.type == .image }
    }

    /// 搜索条目
    /// - Parameter query: 搜索关键词
    /// - Returns: 匹配的条目
    func search(_ query: String) -> [ClipboardEntry] {
        guard !query.isEmpty else { return entries }
        let lower = query.lowercased()
        return entries.filter {
            $0.text.lowercased().contains(lower)
                || $0.preview.lowercased().contains(lower)
        }
    }

    // MARK: - 持久化

    /// 从数据库读回内存缓存
    func load() {
        do {
            entries = try Self.fetchAll(from: storage.database)
            log.info("剪贴板历史已加载，\(self.entries.count, privacy: .public) 条")
        } catch {
            // 读不出来不能让插件起不来：记一条 error，按空历史继续
            log.error("剪贴板历史读取失败，已按空历史继续：\(error)")
            entries = []
        }
    }

    /// 把当前内存状态写回数据库
    ///
    /// 只在退出前需要「确保落盘」时调用 —— 平时的改动已经逐条写过了。
    func save() {
        reloadCacheFromDatabase()
    }

    /// 按数据库里的真实内容重排内存缓存
    ///
    /// 剪枝是在 SQL 里做的（条数与图片预算），内存缓存必须跟着 SQL 的判定走，
    /// 否则界面会显示已经被删掉的条目。
    private func reloadCacheFromDatabase() {
        do {
            entries = try Self.fetchAll(from: storage.database)
        } catch {
            log.error("剪贴板缓存刷新失败：\(error)")
        }
    }

    /// 按图片字节预算剪枝
    ///
    /// 一条 SQL 算清楚「从最新往回累加，累到超出预算为止」：窗口函数给出累计字节数，
    /// 超出预算的那些就是该删的。这比「先算平均大小再换算成条数」精确得多，
    /// 也不需要在内存里过一遍图片数据。
    ///
    /// 单独一次调用而不是塞进 add 的事务：剪枝失败不该让刚写入的条目回滚。
    private func pruneImageBudget() {
        do {
            let budget = imageByteBudget
            let total =
                (try? storage.database.scalarInt(
                    "SELECT SUM(LENGTH(image_data)) AS value FROM clipboard_history")) ?? 0
            guard total > Int64(budget) else { return }

            try storage.database.execute(
                """
                DELETE FROM clipboard_history
                WHERE type = 'image' AND is_pinned = 0 AND is_favorite = 0
                  AND id IN (
                      SELECT id FROM (
                          SELECT id,
                                 SUM(LENGTH(image_data)) OVER (ORDER BY created_at DESC) AS running
                          FROM clipboard_history
                          WHERE type = 'image' AND is_pinned = 0 AND is_favorite = 0
                      )
                      WHERE running > ?
                  )
                """,
                [.int(budget)])
            log.notice("剪贴板图片超出 \(budget, privacy: .public) 字节预算，已按最旧优先剪枝")
            reloadCacheFromDatabase()
        } catch {
            log.error("剪贴板图片剪枝失败：\(error)")
        }
    }

    // MARK: - SQL 片段

    private static let selectColumns = """
        SELECT id, text, image_data, image_size, type, is_favorite, is_pinned, created_at,
               source_app, source_bundle_id
        FROM clipboard_history
        ORDER BY is_pinned DESC, created_at DESC
        """

    private static func fetchAll(from database: SQLiteDatabase) throws -> [ClipboardEntry] {
        try database.query(selectColumns).compactMap(entry(from:))
    }

    /// 一行 → 一个条目
    private static func entry(from row: SQLiteRow) -> ClipboardEntry? {
        guard let idText = row.text("id"), let id = UUID(uuidString: idText),
            let typeText = row.text("type"),
            let type = ClipboardEntry.ContentType(rawValue: typeText)
        else { return nil }

        return ClipboardEntry(
            id: id,
            text: row.text("text") ?? "",
            imageData: row.blob("image_data"),
            imageSizeDescription: row.text("image_size"),
            type: type,
            timestamp: row.date("created_at") ?? Date(),
            isFavorite: row.bool("is_favorite") ?? false,
            isPinned: row.bool("is_pinned") ?? false,
            sourceAppName: row.text("source_app"),
            sourceBundleID: row.text("source_bundle_id")
        )
    }

    private static func insertStatement(for entry: ClipboardEntry) -> SQLiteStatement {
        SQLiteStatement(
            """
            INSERT INTO clipboard_history
                (id, text, image_data, image_size, type, is_favorite, is_pinned, created_at,
                 source_app, source_bundle_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                text = excluded.text,
                image_data = excluded.image_data,
                image_size = excluded.image_size,
                type = excluded.type,
                is_favorite = excluded.is_favorite,
                is_pinned = excluded.is_pinned,
                source_app = excluded.source_app,
                source_bundle_id = excluded.source_bundle_id
            """,
            [
                .text(entry.id.uuidString),
                .text(entry.text),
                entry.imageData.map { SQLiteValue.blob($0) } ?? .null,
                entry.imageSizeDescription.map { SQLiteValue.text($0) } ?? .null,
                .text(entry.type.rawValue),
                .bool(entry.isFavorite),
                .bool(entry.isPinned),
                .date(entry.timestamp),
                entry.sourceAppName.map { SQLiteValue.text($0) } ?? .null,
                entry.sourceBundleID.map { SQLiteValue.text($0) } ?? .null
            ])
    }

    private static func deleteDuplicateTextStatement(for text: String) -> SQLiteStatement {
        SQLiteStatement("DELETE FROM clipboard_history WHERE type != 'image' AND text = ?", [.text(text)])
    }

    private static func deleteDuplicateImageStatement(for data: Data) -> SQLiteStatement {
        SQLiteStatement(
            "DELETE FROM clipboard_history WHERE type = 'image' AND image_data = ?", [.blob(data)])
    }

    /// 条数剪枝：置顶与收藏豁免
    static func pruneStatements(maxEntries: Int) -> [SQLiteStatement] {
        [
            SQLiteStatement(
                """
                DELETE FROM clipboard_history
                WHERE is_pinned = 0 AND is_favorite = 0
                  AND id NOT IN (
                      SELECT id FROM clipboard_history
                      WHERE is_pinned = 0 AND is_favorite = 0
                      ORDER BY created_at DESC
                      LIMIT ?
                  )
                """,
                [.int(maxEntries)])
        ]
    }
}
