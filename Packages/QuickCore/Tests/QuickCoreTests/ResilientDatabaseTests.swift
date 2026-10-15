// ResilientDatabaseTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickCore

@Suite("数据库自愈打开")
struct ResilientDatabaseTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-resilient-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("健康的库原样打开，数据保留")
    func healthyDatabaseOpensAsIs() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("quick.db")

        let first = try SQLiteDatabase(path: url)
        try first.execute("CREATE TABLE t (v TEXT); INSERT INTO t VALUES ('keep');")
        first.close()

        let outcome = try ResilientDatabase.open(at: url)
        guard case .opened(let db) = outcome else {
            Issue.record("健康的库不该被当成损坏：\(outcome)")
            return
        }
        #expect(try db.query("SELECT v FROM t").first?.text("v") == "keep")
    }

    @Test("文件不存在时新建，不算损坏")
    func missingFileIsCreated() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let outcome = try ResilientDatabase.open(at: dir.appendingPathComponent("quick.db"))
        guard case .opened = outcome else {
            Issue.record("首次启动应是 opened：\(outcome)")
            return
        }
    }

    @Test("损坏的库被隔离保存并重建，而不是被删除")
    func corruptDatabaseIsQuarantinedNotDeleted() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("quick.db")
        let garbage = Data(repeating: 0xAB, count: 4096)
        try garbage.write(to: url)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let outcome = try ResilientDatabase.open(at: url, now: now)

        guard case .recovered(let db, let quarantined) = outcome else {
            Issue.record("损坏库应走 recovered：\(outcome)")
            return
        }
        #expect(quarantined.lastPathComponent == "quick.db.corrupt-1700000000")
        #expect(try Data(contentsOf: quarantined) == garbage, "用户的原文件必须原样保留")
        // 新库是可用的
        try db.execute("CREATE TABLE ok (id INTEGER); INSERT INTO ok VALUES (1);")
        #expect(try db.scalarInt("SELECT COUNT(*) AS value FROM ok") == 1)
    }

    @Test("隔离也做不到时退到内存库并说明原因")
    func fallsBackToMemoryWhenDirectoryIsReadOnly() throws {
        let dir = try makeTempDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let url = dir.appendingPathComponent("quick.db")
        try Data(repeating: 0xCD, count: 4096).write(to: url)
        // 目录只读：既不能改名也不能新建
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        let outcome = try ResilientDatabase.open(at: url)
        switch outcome {
        case .inMemory(let db, let reason):
            #expect(db.path == nil)
            #expect(!reason.isEmpty)
        case .recovered, .opened:
            // 以 root 或特殊文件系统运行时权限位不生效，这时不强求
            break
        }
    }
}
