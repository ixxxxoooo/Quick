// CalcHistoryStoreTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import Testing

@testable import PluginCalculator

@MainActor
@Suite("计算历史存储")
struct CalcHistoryStoreTests {

    /// 每个用例一个内存库 + 已建表的存储句柄
    private func makeStore() throws -> CalcHistoryStore {
        let database = try SQLiteDatabase()
        try database.migrate(CalculatorPlugin.storageMigrations)
        return CalcHistoryStore(
            storage: PluginStorage(pluginID: CalculatorPlugin.id, database: database))
    }

    @Test("记录按时间倒序排列")
    func recordsAreNewestFirst() throws {
        let store = try makeStore()

        store.record(expression: "1+1", result: "2")
        store.record(expression: "2+2", result: "4")

        #expect(store.entries.map(\.expression) == ["2+2", "1+1"])
        #expect(store.entries.first?.result == "4")
    }

    @Test("同一个表达式再算一次不新增，而是提到最前并刷新结果")
    func duplicateExpressionMovesToTop() throws {
        let store = try makeStore()

        store.record(expression: "1+1", result: "2")
        store.record(expression: "2+2", result: "4")
        store.record(expression: "1+1", result: "2")

        #expect(store.entries.count == 2)
        #expect(store.entries.map(\.expression) == ["1+1", "2+2"])
    }

    @Test("空白表达式不记录")
    func blankExpressionIsIgnored() throws {
        let store = try makeStore()

        store.record(expression: "   ", result: "0")

        #expect(store.entries.isEmpty)
    }

    @Test("删除与清空")
    func removeAndClear() throws {
        let store = try makeStore()
        store.record(expression: "1+1", result: "2")
        store.record(expression: "2+2", result: "4")

        let first = try #require(store.entries.first)
        store.remove(first.id)
        #expect(store.entries.map(\.expression) == ["1+1"])

        store.clear()
        #expect(store.entries.isEmpty)
    }

    @Test("超出上限时只保留最新的一批")
    func prunesBeyondTheCap() throws {
        let store = try makeStore()

        for index in 0..<(CalcHistoryStore.maxEntries + 5) {
            store.record(expression: "\(index)+0", result: "\(index)")
        }

        #expect(store.entries.count == CalcHistoryStore.maxEntries)
        #expect(store.entries.first?.expression == "\(CalcHistoryStore.maxEntries + 4)+0")
    }

    @Test("换一个 store 实例仍能读回同一条历史（持久化）")
    func survivesReloadFromTheSameDatabase() throws {
        let database = try SQLiteDatabase()
        try database.migrate(CalculatorPlugin.storageMigrations)
        let storage = PluginStorage(pluginID: CalculatorPlugin.id, database: database)

        let first = CalcHistoryStore(storage: storage)
        first.record(expression: "6*7", result: "42")

        let reloaded = CalcHistoryStore(storage: storage)
        #expect(reloaded.entries.map(\.expression) == ["6*7"])
        #expect(reloaded.entries.first?.result == "42")
    }
}
