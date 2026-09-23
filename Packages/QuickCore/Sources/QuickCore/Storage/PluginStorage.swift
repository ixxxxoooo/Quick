// PluginStorage.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 交给插件的存储句柄
///
/// 每个插件拿到的是**已经绑定自己 id** 的句柄。隔离的强度按层区分：
///
/// - **键值层是硬隔离**：每条 SQL 都带 `plugin_id`，插件够不到别人的键。
/// - **真表层是约定隔离**：`database` 是全应用共享的连接，拿到它的插件理论上
///   能碰任何表。插件与宿主同权（编译期插件、一起签名），这里不设运行时沙箱，
///   「只碰自己的表」靠契约维持 —— 这与架构文档「Quick 只支持内置插件」的前提一致。
///
/// 两层能力，按需要选：
///
/// 1. **键值（这一层是默认选择）**：`value(_:forKey:)` / `set(_:forKey:)`，
///    值可以是任意 `Codable`。插件想记住「上次选的是哪个模式」「窗口停在哪」
///    这类零散状态时用它 —— 不需要为一件小事设计文件格式，也不需要自己管
///    原子写入。这是 Fasty `plugin_data` 表的做法。
/// 2. **自己的表**：需要排序、分页、按字段过滤的批量数据（剪贴板历史、笔记、
///    片段）用 `database` 直接写 SQL，schema 通过 `QuickPlugin.storageMigrations`
///    声明。表结构归插件自己所有，宿主不碰。
///
/// 键值层内部就是一个表，`value` 列存 JSON 的 BLOB。之所以不用 `UserDefaults`：
/// 那是放**偏好**的地方（用户可改、要能一键重置、量小），插件数据是**用户内容**
/// （不可重置、会增长、要和别的插件数据一起备份）。两者混在一起，最后会变成
/// 「重置设置把用户笔记也删了」。
public struct PluginStorage: Sendable {

    /// 所属插件 id（写入时自动带上，插件无法伪造）
    public let pluginID: String

    /// 底层数据库，供需要真表的插件使用
    public let database: SQLiteDatabase

    public init(pluginID: String, database: SQLiteDatabase) {
        self.pluginID = pluginID
        self.database = database
    }

    // MARK: - 键值

    /// 读一个值
    ///
    /// 返回 `nil` 表示这个键从没写过。**解码失败会抛错**，而不是静默当作没有 ——
    /// 值类型改了名字或结构时，静默的 `nil` 会让「设置怎么自己没了」变成悬案。
    public func value<T: Codable & Sendable>(_ type: T.Type, forKey key: String) throws -> T? {
        let rows = try database.query(
            "SELECT value FROM plugin_data WHERE plugin_id = ? AND key = ?",
            [.text(pluginID), .text(key)])
        guard let data = rows.first?.blob("value") else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 写一个值（存在则覆盖）
    public func set<T: Codable & Sendable>(_ value: T, forKey key: String) throws {
        let data = try JSONEncoder().encode(value)
        try database.execute(
            """
            INSERT INTO plugin_data (plugin_id, key, value, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(plugin_id, key) DO UPDATE SET value = excluded.value,
                                                      updated_at = excluded.updated_at
            """,
            [.text(pluginID), .text(key), .blob(data), .date(Date())])
    }

    /// 删掉一个键
    public func removeValue(forKey key: String) throws {
        try database.execute(
            "DELETE FROM plugin_data WHERE plugin_id = ? AND key = ?",
            [.text(pluginID), .text(key)])
    }

    /// 本插件写过的所有键
    public func keys() throws -> [String] {
        try database.query(
            "SELECT key FROM plugin_data WHERE plugin_id = ? ORDER BY key",
            [.text(pluginID)]
        ).compactMap { $0.text("key") }
    }

    /// 清空本插件的全部键值数据
    ///
    /// 只在「用户主动重置这个插件」时调用 —— 它删的是用户内容，不是偏好。
    public func removeAll() throws {
        try database.execute(
            "DELETE FROM plugin_data WHERE plugin_id = ?", [.text(pluginID)])
    }
}

// MARK: - 宿主的迁移

public extension SQLiteMigration {

    /// 宿主自己那份 schema：键值表
    ///
    /// 插件各自声明自己的表，宿主不预先建一堆用不上的空表。
    static var corePluginData: SQLiteMigration {
        SQLiteMigration(
            id: "core.plugin_data",
            statements: [
                """
                CREATE TABLE IF NOT EXISTS plugin_data (
                    plugin_id TEXT NOT NULL,
                    key TEXT NOT NULL,
                    value BLOB NOT NULL,
                    updated_at REAL NOT NULL,
                    PRIMARY KEY (plugin_id, key)
                )
                """,
                "CREATE INDEX IF NOT EXISTS idx_plugin_data_pid ON plugin_data(plugin_id)"
            ])
    }
}
