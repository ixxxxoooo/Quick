// UsageHistoryTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickCore

@Suite("最近使用")
struct UsageHistoryTests {

    private func makeHistory() throws -> UsageHistory {
        let database = try SQLiteDatabase()
        try database.migrate([.coreUsageHistory])
        return UsageHistory(database: database)
    }

    @Test("没记录过时返回空")
    func emptyHistory() throws {
        let history = try makeHistory()
        #expect(history.recentItemIDs(limit: 10).isEmpty)
        #expect(history.lastUsed(itemID: "nope") == nil)
    }

    @Test("按最近使用降序返回")
    func ordersByMostRecent() throws {
        let history = try makeHistory()
        let base = Date(timeIntervalSince1970: 1_000_000)

        history.record(itemID: "oldest", at: base)
        history.record(itemID: "middle", at: base.addingTimeInterval(60))
        history.record(itemID: "newest", at: base.addingTimeInterval(120))

        #expect(history.recentItemIDs(limit: 10) == ["newest", "middle", "oldest"])
    }

    @Test("同一个 id 重复使用只更新时间，不产生第二行")
    func recordUpdatesInPlace() throws {
        let history = try makeHistory()
        let base = Date(timeIntervalSince1970: 1_000_000)

        history.record(itemID: "a", at: base)
        history.record(itemID: "b", at: base.addingTimeInterval(10))
        // a 又被用了一次 —— 它应该排到 b 前面，而不是出现两条 a
        history.record(itemID: "a", at: base.addingTimeInterval(20))

        #expect(history.recentItemIDs(limit: 10) == ["a", "b"])
    }

    @Test("limit 生效")
    func limitIsHonoured() throws {
        let history = try makeHistory()
        let base = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<20 {
            history.record(itemID: "item-\(index)", at: base.addingTimeInterval(Double(index)))
        }

        let recent = history.recentItemIDs(limit: 5)
        #expect(recent.count == 5)
        #expect(recent.first == "item-19")
    }

    @Test("清空后回到空状态")
    func removeAll() throws {
        let history = try makeHistory()
        history.record(itemID: "a")
        history.removeAll()
        #expect(history.recentItemIDs(limit: 10).isEmpty)
    }

    @Test("跨实例可见（重启后仍在）")
    func survivesReopen() throws {
        let database = try SQLiteDatabase()
        try database.migrate([.coreUsageHistory])

        UsageHistory(database: database).record(itemID: "persisted")
        // 同一个库上新建一个实例：相当于应用重启
        #expect(UsageHistory(database: database).recentItemIDs(limit: 5) == ["persisted"])
    }
}
