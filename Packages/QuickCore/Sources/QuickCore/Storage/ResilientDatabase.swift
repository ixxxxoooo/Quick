// ResilientDatabase.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 「打不开就自愈」的数据库打开流程
///
/// 以前数据库文件损坏时只有两种结局：直接退到内存库（本次运行的数据全部不落盘），
/// 或者带着坏库继续跑，让每个插件各自以「读取失败」的形式炸开。
/// 这里把流程定成三级降级，并且**绝不删除用户的文件**：
///
/// 1. 能打开且 `PRAGMA quick_check` 通过 → 正常使用；
/// 2. 打不开或自检失败 → 把坏库（连同 `-wal` / `-shm`）改名为 `quick.db.corrupt-<时间戳>`
///    留给用户排查，再在原路径新建一个干净的库 → `recovered`；
/// 3. 连新建都失败（磁盘只读 / 满）→ 内存库，本次运行不落盘 → `inMemory`。
public enum ResilientDatabase {

    /// 打开结果
    public enum Outcome {
        /// 一切正常
        case opened(SQLiteDatabase)
        /// 原库已损坏并被隔离到 `quarantined`，当前用的是新建的库
        case recovered(SQLiteDatabase, quarantined: URL)
        /// 磁盘库不可用，退到内存库
        case inMemory(SQLiteDatabase, reason: String)

        public var database: SQLiteDatabase {
            switch self {
            case .opened(let db), .recovered(let db, _), .inMemory(let db, _): return db
            }
        }
    }

    /// 隔离文件的后缀前缀
    public static let quarantineMarker = ".corrupt-"

    /// 打开数据库
    ///
    /// - Parameters:
    ///   - url: 数据库文件
    ///   - fileManager: 文件系统；测试传自己的
    ///   - now: 当前时间（决定隔离文件名）；测试固定它
    /// - Throws: 仅当连内存库都无法创建时
    public static func open(
        at url: URL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> Outcome {
        var failure: String
        do {
            let db = try SQLiteDatabase(path: url)
            if let problem = integrityProblem(of: db) {
                db.close()
                failure = "完整性自检未通过：\(problem)"
            } else {
                return .opened(db)
            }
        } catch {
            failure = "打不开：\(error)"
        }

        // 文件不存在时 open 会新建，走到这里说明确实有问题；隔离已有文件
        if let quarantined = quarantine(url, fileManager: fileManager, now: now) {
            do {
                let fresh = try SQLiteDatabase(path: url)
                QuickLog.app.error(
                    "数据库\(failure, privacy: .public)；已隔离到 \(quarantined.lastPathComponent, privacy: .public) 并新建")
                return .recovered(fresh, quarantined: quarantined)
            } catch {
                failure += "；新建也失败：\(error)"
            }
        }
        return .inMemory(try SQLiteDatabase(), reason: failure)
    }

    /// 自检；通过返回 nil，否则返回问题描述
    static func integrityProblem(of db: SQLiteDatabase) -> String? {
        do {
            let rows = try db.query("PRAGMA quick_check")
            guard let row = rows.first, let column = row.columns.first,
                let verdict = row.text(column)
            else { return "自检没有返回结果" }
            return verdict == "ok" ? nil : verdict
        } catch {
            return "\(error)"
        }
    }

    /// 把库文件及其 WAL 伴生文件改名隔离
    ///
    /// - Returns: 隔离后的主库路径；原文件不存在或改名失败时返回 nil
    static func quarantine(_ url: URL, fileManager: FileManager, now: Date) -> URL? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let stamp = Int(now.timeIntervalSince1970)
        let target = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + quarantineMarker + String(stamp))
        do {
            try fileManager.moveItem(at: url, to: target)
        } catch {
            QuickLog.app.error("隔离损坏数据库失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: url.path + suffix)
            if fileManager.fileExists(atPath: side.path) {
                try? fileManager.moveItem(
                    at: side, to: URL(fileURLWithPath: target.path + suffix))
            }
        }
        return target
    }
}
