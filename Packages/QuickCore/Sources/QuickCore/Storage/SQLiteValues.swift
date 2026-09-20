// SQLiteValues.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 绑定到 SQL 语句上的一个值
///
/// SQLite 只有五种存储类别，所以绑定值也就是这五种 —— 类型系统里写清楚，
/// 比到处传 `Any` 让运行期去猜要好。
public enum SQLiteValue: Sendable, Equatable {
    case null
    case int(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public static func int(_ value: Int) -> SQLiteValue { .int(Int64(value)) }
    public static func bool(_ value: Bool) -> SQLiteValue { .int(value ? 1 : 0) }
    public static func date(_ value: Date) -> SQLiteValue { .real(value.timeIntervalSince1970) }
}

/// 查询结果里的一行
///
/// 按列名取值，取不到（列不存在、类型不符）返回 nil —— 让调用点用 `??` 决定默认值，
/// 而不是在这里替它决定。
public struct SQLiteRow: Sendable {

    private let storage: [String: SQLiteValue]

    init(storage: [String: SQLiteValue]) {
        self.storage = storage
    }

    /// 列名列表（用于排查「SQL 写错了列名」这类问题）
    public var columns: [String] { Array(storage.keys) }

    public func value(_ column: String) -> SQLiteValue? {
        storage[column]
    }

    public func text(_ column: String) -> String? {
        if case .text(let value) = storage[column] { return value }
        return nil
    }

    public func int(_ column: String) -> Int64? {
        switch storage[column] {
        case .int(let value): return value
        // SQLite 会把整数存成 REAL 的场景存在（例如表达式结果），这里一并接受
        case .real(let value): return Int64(value)
        default: return nil
        }
    }

    public func double(_ column: String) -> Double? {
        switch storage[column] {
        case .real(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    public func bool(_ column: String) -> Bool? {
        int(column).map { $0 != 0 }
    }

    public func blob(_ column: String) -> Data? {
        if case .blob(let value) = storage[column] { return value }
        return nil
    }

    public func date(_ column: String) -> Date? {
        double(column).map(Date.init(timeIntervalSince1970:))
    }

    /// 取一个非空字符串，缺失时抛错
    ///
    /// 用于「这一列在 schema 里就是 NOT NULL」的场合：与其静默给个空串，
    /// 不如让坏数据当场暴露。
    public func requiredText(_ column: String) throws -> String {
        guard let value = text(column) else {
            throw SQLiteError.missingColumn(column)
        }
        return value
    }
}

/// 一条带参数的语句
///
/// 事务按「一批语句」提交，而不是回调闭包：这样事务边界在调用点一眼可见，
/// 也避免把一个同步资源包进闭包里再和并发隔离较劲。
public struct SQLiteStatement: Sendable {

    public let sql: String
    public let bindings: [SQLiteValue]

    public init(_ sql: String, _ bindings: [SQLiteValue] = []) {
        self.sql = sql
        self.bindings = bindings
    }
}

/// SQLite 操作失败
public enum SQLiteError: Error, CustomStringConvertible {

    /// 打开数据库失败
    case openFailed(path: String, message: String)
    /// 执行 SQL 失败
    case executionFailed(sql: String, message: String)
    /// 结果里缺少期望的列
    case missingColumn(String)
    /// 数据库已关闭
    case closed

    public var description: String {
        switch self {
        case .openFailed(let path, let message):
            return "打开数据库失败（\(path)）：\(message)"
        case .executionFailed(let sql, let message):
            return "执行 SQL 失败：\(message)｜SQL: \(sql)"
        case .missingColumn(let column):
            return "结果里缺少列：\(column)"
        case .closed:
            return "数据库已关闭"
        }
    }
}
