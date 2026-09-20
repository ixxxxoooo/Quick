// SQLiteDatabaseTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickCore

@Suite("SQLiteDatabase")
struct SQLiteDatabaseTests {

    private func makeDatabase() throws -> SQLiteDatabase {
        try SQLiteDatabase()
    }

    // MARK: - 基本读写

    @Test("建表、插入、查询走通")
    func basicRoundTrip() throws {
        let db = try makeDatabase()
        try db.execute("CREATE TABLE t (id TEXT PRIMARY KEY, count INTEGER, score REAL, note TEXT)")

        try db.execute(
            "INSERT INTO t (id, count, score, note) VALUES (?, ?, ?, ?)",
            [.text("a"), .int(7), .real(1.5), .text("你好")])

        let rows = try db.query("SELECT * FROM t")
        #expect(rows.count == 1)
        #expect(rows.first?.text("id") == "a")
        #expect(rows.first?.int("count") == 7)
        #expect(rows.first?.double("score") == 1.5)
        #expect(rows.first?.text("note") == "你好")
    }

    @Test("参数绑定不会被 SQL 注入改写")
    func bindingsAreNotInterpolated() throws {
        let db = try makeDatabase()
        try db.execute("CREATE TABLE t (note TEXT)")
        try db.execute("INSERT INTO t (note) VALUES (?)", [.text("'); DROP TABLE t; --")])

        #expect(try db.tableExists("t"))
        #expect(try db.query("SELECT * FROM t").first?.text("note") == "'); DROP TABLE t; --")
    }

    @Test("NULL 与空值能区分开")
    func nullIsDistinctFromEmpty() throws {
        let db = try makeDatabase()
        try db.execute("CREATE TABLE t (id TEXT, note TEXT)")
        try db.execute("INSERT INTO t (id, note) VALUES (?, NULL)", [.text("null-note")])
        try db.execute("INSERT INTO t (id, note) VALUES (?, ?)", [.text("empty-note"), .text("")])

        let rows = try db.query("SELECT * FROM t ORDER BY id")
        #expect(rows.count == 2)
        // NULL 读不到文本，空串读得到空串 —— 这个区别是「用户清空了内容」和
        // 「这一列本来就没有」的分界，不能混
        #expect(rows[0].text("note") == "")
        #expect(rows[1].text("note") == nil)
    }

    // MARK: - 二进制

    @Test("BLOB 原样往返（含空 blob 与图片尺寸的数据）")
    func blobRoundTrip() throws {
        let db = try makeDatabase()
        try db.execute("CREATE TABLE t (id TEXT, data BLOB)")

        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0xAB, count: 5000))
        try db.execute("INSERT INTO t (id, data) VALUES (?, ?)", [.text("img"), .blob(png)])
        try db.execute("INSERT INTO t (id, data) VALUES (?, ?)", [.text("empty"), .blob(Data())])
        try db.execute("INSERT INTO t (id, data) VALUES (?, ?)", [.text("null"), .null])

        let rows = try db.query("SELECT * FROM t ORDER BY id")
        #expect(rows[0].blob("data") == Data())
        #expect(rows[1].blob("data") == png)
        #expect(rows[2].blob("data") == nil)
    }

    @Test("能用 SQL 直接算出 blob 总字节数")
    func blobSizeIsQueryable() throws {
        // 剪贴板的图片预算就靠这个查询，不用把数据读进内存
        let db = try makeDatabase()
        try db.execute("CREATE TABLE t (data BLOB)")
        try db.execute("INSERT INTO t (data) VALUES (?)", [.blob(Data(repeating: 1, count: 100))])
        try db.execute("INSERT INTO t (data) VALUES (?)", [.blob(Data(repeating: 2, count: 250))])

        #expect(try db.scalarInt("SELECT SUM(LENGTH(data)) AS value FROM t") == 350)
    }

    // MARK: - 事务

    @Test("事务里有一条失败则整批回滚")
    func transactionRollsBackOnFailure() throws {
        let db = try makeDatabase()
        try db.execute("CREATE TABLE t (id TEXT PRIMARY KEY, n INTEGER)")

        #expect(throws: SQLiteError.self) {
            try db.transaction([
                SQLiteStatement("INSERT INTO t (id, n) VALUES (?, ?)", [.text("a"), .int(1)]),
                // 主键冲突：这一条失败，前面那条也不能留下
                SQLiteStatement("INSERT INTO t (id, n) VALUES (?, ?)", [.text("a"), .int(2)])
            ])
        }

        #expect(try db.scalarInt("SELECT COUNT(*) AS value FROM t") == 0)
    }

    @Test("事务成功后全部可见")
    func transactionCommits() throws {
        let db = try makeDatabase()
        try db.execute("CREATE TABLE t (id TEXT PRIMARY KEY, n INTEGER)")

        try db.transaction([
            SQLiteStatement("INSERT INTO t (id, n) VALUES (?, ?)", [.text("a"), .int(1)]),
            SQLiteStatement("INSERT INTO t (id, n) VALUES (?, ?)", [.text("b"), .int(2)])
        ])

        #expect(try db.scalarInt("SELECT COUNT(*) AS value FROM t") == 2)
    }

    @Test("空事务列表是安全的空操作")
    func emptyTransactionIsNoop() throws {
        let db = try makeDatabase()
        try db.transaction([])
        #expect(try db.tableExists("schema_migrations"))
    }

    // MARK: - 迁移

    @Test("迁移按 id 记账，重复调用不会重跑")
    func migrationsAreIdempotent() throws {
        let db = try makeDatabase()
        let migration = SQLiteMigration(
            id: "test.first",
            statements: ["CREATE TABLE t (id TEXT PRIMARY KEY)"])

        try db.migrate([migration])
        #expect(try db.tableExists("t"))
        #expect(try db.appliedMigrationIDs() == ["test.first"])

        // 再跑一次：表已存在，若重复执行会因 "table t already exists" 抛错
        try db.migrate([migration])
        #expect(try db.appliedMigrationIDs() == ["test.first"])
    }

    @Test("后续迁移可以在已存在的表上加列")
    func laterMigrationAltersTable() throws {
        let db = try makeDatabase()
        try db.migrate([
            SQLiteMigration(id: "test.v1", statements: ["CREATE TABLE t (id TEXT PRIMARY KEY)"])
        ])
        try db.migrate([
            SQLiteMigration(
                id: "test.v2",
                statements: ["ALTER TABLE t ADD COLUMN note TEXT NOT NULL DEFAULT ''"])
        ])

        #expect(try db.columns(of: "t").contains("note"))
        #expect(try db.appliedMigrationIDs() == ["test.v1", "test.v2"])
    }

    @Test("迁移失败不会留下半截 schema")
    func failedMigrationRollsBack() throws {
        let db = try makeDatabase()
        let broken = SQLiteMigration(
            id: "test.broken",
            statements: [
                "CREATE TABLE t (id TEXT PRIMARY KEY)",
                "CREATE TABLE t (id TEXT PRIMARY KEY)"  // 同名表：必然失败
            ])

        #expect(throws: SQLiteError.self) { try db.migrate([broken]) }

        // 整批回滚：表不该存在，账本里也不该有它
        #expect(try db.tableExists("t") == false)
        #expect(try db.appliedMigrationIDs().isEmpty)
    }

    @Test("多方各自声明迁移，互不影响")
    func migrationsFromMultipleOwners() throws {
        // 宿主一份、插件两份：id 独立，不需要协调编号
        let db = try makeDatabase()
        try db.migrate([
            SQLiteMigration(id: "core.plugin_data", statements: ["CREATE TABLE core_t (id TEXT)"]),
            SQLiteMigration(id: "clipboard.history", statements: ["CREATE TABLE clip_t (id TEXT)"]),
            SQLiteMigration(id: "notes.items", statements: ["CREATE TABLE note_t (id TEXT)"])
        ])

        #expect(try db.tableExists("core_t"))
        #expect(try db.tableExists("clip_t"))
        #expect(try db.tableExists("note_t"))
    }

    // MARK: - 关闭与错误

    @Test("关闭之后再用会抛错，而不是崩")
    func closedDatabaseThrows() throws {
        let db = try makeDatabase()
        db.close()
        #expect(throws: SQLiteError.self) { try db.execute("SELECT 1") }
    }

    @Test("SQL 写错时抛出带 SQL 的错误")
    func invalidSQLReportsSQL() throws {
        let db = try makeDatabase()
        do {
            try db.execute("SELEC 1")
            Issue.record("本该抛错")
        } catch let error as SQLiteError {
            #expect(error.description.contains("SELEC 1"))
        }
    }

    @Test("内存库之间互不干扰")
    func inMemoryDatabasesAreIsolated() throws {
        let first = try makeDatabase()
        let second = try makeDatabase()
        try first.execute("CREATE TABLE only_in_first (id TEXT)")

        #expect(try first.tableExists("only_in_first"))
        #expect(try second.tableExists("only_in_first") == false)
    }
}

// MARK: - 插件存储

@Suite("PluginStorage")
struct PluginStorageTests {

    private func makeStorage(pluginID: String = "clipboard") throws -> (PluginStorage, SQLiteDatabase) {
        let db = try SQLiteDatabase()
        try db.migrate([.corePluginData])
        return (PluginStorage(pluginID: pluginID, database: db), db)
    }

    private struct Preferences: Codable, Sendable, Equatable {
        var mode: String
        var count: Int
    }

    @Test("值往返（结构体、数组、可选）")
    func valueRoundTrip() throws {
        let (storage, _) = try makeStorage()

        try storage.set(Preferences(mode: "encode", count: 3), forKey: "prefs")
        #expect(try storage.value(Preferences.self, forKey: "prefs") == Preferences(mode: "encode", count: 3))

        try storage.set(["a", "b"], forKey: "list")
        #expect(try storage.value([String].self, forKey: "list") == ["a", "b"])

        try storage.set(Data([1, 2, 3]), forKey: "blob")
        #expect(try storage.value(Data.self, forKey: "blob") == Data([1, 2, 3]))
    }

    @Test("没写过的键返回 nil")
    func missingKeyIsNil() throws {
        let (storage, _) = try makeStorage()
        #expect(try storage.value(Preferences.self, forKey: "nope") == nil)
    }

    @Test("同一个键重复写会覆盖而不是插入第二行")
    func setOverwrites() throws {
        let (storage, db) = try makeStorage()
        try storage.set(1, forKey: "n")
        try storage.set(2, forKey: "n")

        #expect(try storage.value(Int.self, forKey: "n") == 2)
        #expect(try db.scalarInt("SELECT COUNT(*) AS value FROM plugin_data") == 1)
    }

    @Test("键值按插件隔离，一个插件读不到另一个的")
    func valuesAreNamespaced() throws {
        let db = try SQLiteDatabase()
        try db.migrate([.corePluginData])
        let clipboard = PluginStorage(pluginID: "clipboard", database: db)
        let notes = PluginStorage(pluginID: "notes", database: db)

        try clipboard.set("剪贴板的值", forKey: "shared-name")
        try notes.set("笔记的值", forKey: "shared-name")

        // 键名相同也不会串
        #expect(try clipboard.value(String.self, forKey: "shared-name") == "剪贴板的值")
        #expect(try notes.value(String.self, forKey: "shared-name") == "笔记的值")
        #expect(try clipboard.keys() == ["shared-name"])
    }

    @Test("删除单个键与清空整个命名空间")
    func removeKeyAndNamespace() throws {
        let (storage, _) = try makeStorage()
        try storage.set("a", forKey: "one")
        try storage.set("b", forKey: "two")

        try storage.removeValue(forKey: "one")
        #expect(try storage.value(String.self, forKey: "one") == nil)
        #expect(try storage.keys() == ["two"])

        try storage.removeAll()
        #expect(try storage.keys().isEmpty)
    }

    @Test("解码失败会抛错，而不是静默返回 nil")
    func decodeFailureThrows() throws {
        let (storage, db) = try makeStorage()
        // 手工塞进一个类型对不上的值，模拟「值类型改了结构」的场景
        try db.execute(
            "INSERT INTO plugin_data (plugin_id, key, value, updated_at) VALUES (?, ?, ?, ?)",
            [.text("clipboard"), .text("prefs"), .blob(Data(#"{"unexpected":true}"#.utf8)), .date(Date())])

        #expect(throws: (any Error).self) {
            try storage.value(Preferences.self, forKey: "prefs")
        }
    }

    @Test("插件能拿到自己的键列表，按名排序")
    func keysAreSorted() throws {
        let (storage, _) = try makeStorage()
        try storage.set(1, forKey: "zebra")
        try storage.set(2, forKey: "apple")
        #expect(try storage.keys() == ["apple", "zebra"])
    }
}
