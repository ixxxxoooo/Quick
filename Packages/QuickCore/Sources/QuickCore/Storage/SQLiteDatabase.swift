// SQLiteDatabase.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import SQLite3
import Synchronization

/// 一个 SQLite 数据库
///
/// ## 为什么是同步 API，而不是 actor
///
/// 存储的调用点全都在同步路径上：插件的 `activate()` 是同步的，视图直接在 body 里
/// 读 store 的数组。把这里做成 actor，`await` 会顺着调用链传染到插件的生命周期和
/// 所有视图，换来的并发收益却是零 —— 本地 SQLite 的一次写入是微秒级，而且写操作
/// 本来就要串行。所以这里用 `Mutex` 保护句柄：`Sendable` 是编译器保证的（不是
/// `@unchecked`），调用点保持同步。
///
/// ## 并发语义
///
/// 开 WAL 之后 SQLite 支持「1 写 + N 读」，但本类把所有访问串行化。Quick 的数据量
/// （几千条剪贴板、几百条笔记）下串行化的代价可以忽略，换来的是「不会有两个线程
/// 同时碰一个连接」这个不需要动脑的前提。
public final class SQLiteDatabase: Sendable {

    /// sqlite3 句柄，`nil` 表示已关闭
    private let handle: Mutex<OpaquePointer?>

    /// 数据库文件路径（内存库为 nil），用于日志与错误信息
    public let path: String?

    // MARK: - 打开 / 关闭

    /// 打开（或创建）磁盘上的数据库
    public init(path: URL) throws {
        self.path = path.path
        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path.path, &pointer, flags, nil)
        guard result == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "无法分配句柄"
            sqlite3_close_v2(pointer)
            throw SQLiteError.openFailed(path: path.path, message: message)
        }
        self.handle = Mutex(pointer)
        try configure()
    }

    /// 内存数据库（测试用）
    ///
    /// 每个实例一个独立的库，互不干扰 —— 测存储不用碰磁盘，也不用清临时目录。
    public init() throws {
        self.path = nil
        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(":memory:", &pointer, flags, nil) == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "无法分配句柄"
            sqlite3_close_v2(pointer)
            throw SQLiteError.openFailed(path: ":memory:", message: message)
        }
        self.handle = Mutex(pointer)
        try configure()
    }

    deinit {
        handle.withLock { pointer in
            if let pointer { sqlite3_close_v2(pointer) }
            pointer = nil
        }
    }

    /// 关闭连接
    ///
    /// 退出路径上显式调用：`deinit` 也会关，但退出时我们想把 WAL 干净地合并回主库。
    public func close() {
        handle.withLock { pointer in
            if let pointer {
                // 合并 WAL 并截断，避免退出后留下 -wal / -shm 残留
                sqlite3_exec(pointer, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
                sqlite3_close_v2(pointer)
            }
            pointer = nil
        }
    }

    /// 连接级 PRAGMA
    ///
    /// 与 Fasty 的选择一致：WAL 让读写不互相阻塞，`busy_timeout` 把偶发的锁冲突
    /// 变成等待而不是立刻失败，`synchronous=NORMAL` 在 WAL 下仍然安全（掉电最多丢
    /// 最后一个事务），`foreign_keys` 打开以便将来用外键做级联删除。
    private func configure() throws {
        try execute(
            """
            PRAGMA journal_mode=WAL;
            PRAGMA busy_timeout=5000;
            PRAGMA synchronous=NORMAL;
            PRAGMA foreign_keys=ON;

            -- 迁移账本必须最先存在，它自己不是一次迁移
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id TEXT PRIMARY KEY,
                applied_at REAL NOT NULL
            );
            """)
    }

    // MARK: - 执行

    /// 执行一段（可以含多条语句的）SQL，不需要参数时用它
    public func execute(_ sql: String) throws {
        try handle.withLock { pointer in
            let connection = try Self.require(pointer, sql: sql)
            var errorMessage: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(connection, sql, nil, nil, &errorMessage)
            if result != SQLITE_OK {
                let message = errorMessage.map { String(cString: $0) } ?? "未知错误"
                sqlite3_free(errorMessage)
                throw SQLiteError.executionFailed(sql: sql, message: message)
            }
        }
    }

    /// 执行一条带参数的语句
    public func execute(_ sql: String, _ bindings: [SQLiteValue]) throws {
        try handle.withLock { pointer in
            let connection = try Self.require(pointer, sql: sql)
            let statement = try PreparedStatement(connection: connection, sql: sql, bindings: bindings)
            defer { statement.finalize() }
            try statement.stepToCompletion()
        }
    }

    /// 在一个事务里执行一批语句
    ///
    /// 要么全成，要么全不成。用法是「把一次业务动作需要的语句都列出来」，
    /// 例如「插入一条剪贴板记录 + 删掉超限的旧记录」—— 这两件事必须同时发生，
    /// 否则崩在中间会留下一个超限的历史。
    public func transaction(_ statements: [SQLiteStatement]) throws {
        guard !statements.isEmpty else { return }
        try handle.withLock { pointer in
            let connection = try Self.require(pointer, sql: "BEGIN IMMEDIATE")
            try Self.exec(connection, "BEGIN IMMEDIATE")
            do {
                for statement in statements {
                    let prepared = try PreparedStatement(
                        connection: connection, sql: statement.sql, bindings: statement.bindings)
                    defer { prepared.finalize() }
                    try prepared.stepToCompletion()
                }
                try Self.exec(connection, "COMMIT")
            } catch {
                // 回滚失败时保留原始错误：原始错误才是用户该看到的那条
                try? Self.exec(connection, "ROLLBACK")
                throw error
            }
        }
    }

    // MARK: - 查询

    /// 查询并一次读完结果
    public func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        try handle.withLock { pointer in
            let connection = try Self.require(pointer, sql: sql)
            let statement = try PreparedStatement(connection: connection, sql: sql, bindings: bindings)
            defer { statement.finalize() }
            return try statement.readRows()
        }
    }

    /// 查询单个整数（`COUNT(*)`、`SUM(...)` 这类）
    public func scalarInt(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> Int64? {
        try query(sql, bindings).first?.int("value")
    }

    // MARK: - 迁移

    /// 应用尚未执行过的迁移
    ///
    /// 每个迁移一个事务：迁移脚本写坏了，数据库会停在**上一个完整状态**，
    /// 而不是留在一个改了一半的表结构上。
    ///
    /// 用字符串 id 而不是递增版本号，是因为 schema 由多方声明 —— 宿主一份，每个
    /// 插件各一份。递增编号会强迫所有插件去协调「谁拿 7 谁拿 8」，加一个插件就要
    /// 动别人的编号；字符串 id（`core.plugin_data`、`clipboard.history`）各自独立，
    /// 加插件不需要碰任何人。
    ///
    /// - Parameter migrations: 按给定顺序尝试；已应用过的（id 在账本里）直接跳过。
    public func migrate(_ migrations: [SQLiteMigration]) throws {
        guard !migrations.isEmpty else { return }

        let applied = try appliedMigrationIDs()
        for migration in migrations where !applied.contains(migration.id) {
            // 事务边界由 transaction(_:) 负责，这里只列语句 —— 自己再写一次 BEGIN
            // 会变成「事务里开事务」，SQLite 直接拒绝
            var statements = migration.statements.map { SQLiteStatement($0) }
            statements.append(
                SQLiteStatement(
                    "INSERT INTO schema_migrations (id, applied_at) VALUES (?, ?)",
                    [.text(migration.id), .date(Date())]))
            do {
                try transaction(statements)
            } catch {
                throw SQLiteError.executionFailed(
                    sql: "migrate \(migration.id)", message: "\(error)")
            }
        }
    }

    /// 已应用的迁移 id
    public func appliedMigrationIDs() throws -> Set<String> {
        // 账本表还没建起来的场景：configure 里已经建了，所以这里只可能是被外部改坏
        guard try tableExists("schema_migrations") else { return [] }
        return Set(try query("SELECT id FROM schema_migrations").compactMap { $0.text("id") })
    }

    /// 表是否存在（迁移测试用）
    public func tableExists(_ name: String) throws -> Bool {
        let rows = try query(
            "SELECT COUNT(*) AS value FROM sqlite_master WHERE type = 'table' AND name = ?",
            [.text(name)])
        return (rows.first?.int("value") ?? 0) > 0
    }

    /// 某个表的列名（迁移测试用：确认新增的列真的加上了）
    public func columns(of table: String) throws -> [String] {
        try query("PRAGMA table_info(\(table))").compactMap { $0.text("name") }
    }

    // MARK: - 内部

    private static func require(_ pointer: OpaquePointer?, sql: String) throws -> OpaquePointer {
        guard let pointer else { throw SQLiteError.closed }
        _ = sql
        return pointer
    }

    private static func exec(_ connection: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(connection, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "未知错误"
            sqlite3_free(errorMessage)
            throw SQLiteError.executionFailed(sql: sql, message: message)
        }
    }
}

// MARK: - 迁移

/// 一次 schema 迁移
///
/// id + 该迁移要执行的 SQL。宿主与插件各自声明自己的那一份，由
/// `SQLiteDatabase.migrate` 按 id 去重后应用。id 一旦发布就不能改 ——
/// 它就是「这段 DDL 有没有跑过」的判据。
public struct SQLiteMigration: Sendable {

    public let id: String
    public let statements: [String]

    public init(id: String, statements: [String]) {
        self.id = id
        self.statements = statements
    }
}

// MARK: - 预编译语句

/// 一条预编译语句
///
/// 只在本文件内使用：对外暴露的是 `execute` / `query` / `transaction`，
/// 调用点不该自己管 `sqlite3_stmt` 的生命周期。
private final class PreparedStatement {

    private let connection: OpaquePointer
    private let sql: String
    private var statement: OpaquePointer?

    /// SQLite 要求它自己拷贝绑定进去的字符串/二进制数据
    ///
    /// C 里的 `SQLITE_TRANSIENT` 是 `(sqlite3_destructor_type)-1`。Swift 既没有导入
    /// `sqlite3_destructor_type` 这个 typedef，也拿不到那个宏，所以按它的真实类型
    /// 声明一个函数指针，再把 -1 转过去。
    private static let transient = unsafeBitCast(
        -1, to: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)

    init(connection: OpaquePointer, sql: String, bindings: [SQLiteValue]) throws {
        self.connection = connection
        self.sql = sql

        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(connection))
            sqlite3_finalize(statement)
            statement = nil
            throw SQLiteError.executionFailed(sql: sql, message: message)
        }

        for (offset, binding) in bindings.enumerated() {
            try bind(binding, at: Int32(offset + 1))
        }
    }

    func finalize() {
        sqlite3_finalize(statement)
        statement = nil
    }

    /// 跑到结束，不关心结果行（写操作走这条）
    func stepToCompletion() throws {
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return }
            if result == SQLITE_ROW { continue }
            throw SQLiteError.executionFailed(
                sql: sql, message: String(cString: sqlite3_errmsg(connection)))
        }
    }

    /// 读完全部结果行
    func readRows() throws -> [SQLiteRow] {
        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else {
                throw SQLiteError.executionFailed(
                    sql: sql, message: String(cString: sqlite3_errmsg(connection)))
            }
            rows.append(readRow())
        }
    }

    private func readRow() -> SQLiteRow {
        var storage: [String: SQLiteValue] = [:]
        let columnCount = sqlite3_column_count(statement)
        for index in 0..<columnCount {
            guard let namePointer = sqlite3_column_name(statement, index) else { continue }
            let name = String(cString: namePointer)
            storage[name] = readValue(at: index)
        }
        return SQLiteRow(storage: storage)
    }

    private func readValue(at index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .int(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let pointer = sqlite3_column_text(statement, index) else { return .null }
            return .text(String(cString: pointer))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, index))
            guard count > 0, let pointer = sqlite3_column_blob(statement, index) else {
                return .blob(Data())
            }
            return .blob(Data(bytes: pointer, count: count))
        default:
            return .null
        }
    }

    private func bind(_ value: SQLiteValue, at index: Int32) throws {
        let result: Int32
        switch value {
        case .null:
            result = sqlite3_bind_null(statement, index)
        case .int(let number):
            result = sqlite3_bind_int64(statement, index, number)
        case .real(let number):
            result = sqlite3_bind_double(statement, index, number)
        case .text(let string):
            result = string.withCString { pointer in
                sqlite3_bind_text(statement, index, pointer, -1, Self.transient)
            }
        case .blob(let data):
            if data.isEmpty {
                // 长度 0 且指针为 NULL 会被 SQLite 读成 NULL，而我们已经有 .null 表达它了。
                // 空 blob 必须给一个非空指针，所以借一个字节的地址来用。
                var placeholder: UInt8 = 0
                result = withUnsafePointer(to: &placeholder) { pointer in
                    sqlite3_bind_blob(statement, index, pointer, 0, Self.transient)
                }
            } else {
                result = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(
                        statement, index, buffer.baseAddress, Int32(buffer.count), Self.transient)
                }
            }
        }
        guard result == SQLITE_OK else {
            throw SQLiteError.executionFailed(
                sql: sql, message: "绑定第 \(index) 个参数失败")
        }
    }
}
