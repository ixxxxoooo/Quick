// PaletteSearchEngineTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Synchronization
import Testing

@testable import QuickUI
import QuickCore

/// 跨线程记录插件是否被调用、是否观察到取消
///
/// 测试要断言的正是「插件有没有被叫醒」，这个可变量必须能在
/// `nonisolated` 的 `dynamicSearch` 与主 actor 的断言之间共享。
private final class CallLog: Sendable {

    private let calls = Mutex<[String: Int]>([:])
    private let cancellations = Mutex<[String: Bool]>([:])

    func recordCall(_ pluginID: String) {
        calls.withLock { $0[pluginID, default: 0] += 1 }
    }

    func callCount(_ pluginID: String) -> Int {
        calls.withLock { $0[pluginID] ?? 0 }
    }

    func recordCancellation(_ pluginID: String) {
        cancellations.withLock { $0[pluginID] = true }
    }

    func didObserveCancellation(_ pluginID: String) -> Bool {
        cancellations.withLock { $0[pluginID] ?? false }
    }
}

/// 空查询时露一条入口，并按关键词产出动态结果
private final class StubPlugin: QuickPlugin {

    static let id = "stub"
    static let name = "Stub"
    static let icon = "circle"
    static let triggerWords = ["stub"]
    static let functionCommands = [
        CommandDescriptor(
            id: "stub.open-thing", pluginID: id, pluginName: name, title: "打开东西",
            keywords: ["thing"], icon: "circle",
            showsWhenQueryEmpty: true)
    ]

    let log: CallLog
    var isEnabled = true

    init(log: CallLog = CallLog()) {
        self.log = log
    }

    /// 闸门必须真的会开，否则「关闭来源后不参与」这类测试永远通过
    nonisolated func accepts(query: String) -> Bool {
        query.localizedCaseInsensitiveContains(Self.triggerWords[0])
    }

    nonisolated func dynamicSearch(query: String) async -> [SearchableItem] {
        log.recordCall(Self.id)
        return [
            SearchableItem(
                id: "\(Self.id).dynamic", pluginID: Self.id, title: "动态结果 \(query)",
                icon: Self.icon, action: {})
        ]
    }
}

/// 一直不返回的插件，用来验证超时与取消
private final class HangingPlugin: QuickPlugin {

    static let id = "hang"
    static let name = "Hang"
    static let icon = "clock"
    static let triggerWords = ["hang"]

    let log: CallLog
    var isEnabled = true

    init(log: CallLog) {
        self.log = log
    }

    nonisolated func accepts(query: String) -> Bool { true }

    nonisolated func dynamicSearch(query: String) async -> [SearchableItem] {
        log.recordCall(Self.id)
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            log.recordCancellation(Self.id)
            return []
        }
        return []
    }
}

@Suite("聚合搜索")
@MainActor
struct PaletteSearchEngineTests {

    private func makeCommands() -> [IndexedCommand] {
        [
            IndexedCommand(
                CommandDescriptor(
                    id: "alpha.go", pluginID: "alpha", pluginName: "Alpha", title: "Alpha 执行",
                    keywords: ["run"], icon: "play", showsWhenQueryEmpty: true)),
            IndexedCommand(
                CommandDescriptor(
                    id: "beta.go", pluginID: "beta", pluginName: "Beta", title: "Beta 执行",
                    keywords: ["run"], icon: "play", showsWhenQueryEmpty: false))
        ]
    }

    /// 空查询走的是同步路径，取值必须与非空时一致 ——
    /// 这条路径曾经被无条件丢进 `Task.detached`，在多线程跳转上白等 100 ms。
    @Test("空查询返回每个插件的入口命令")
    func emptyQueryReturnsEntryPoints() async {
        let outcome = await PaletteSearchEngine.search(
            query: "   ",
            staticCommands: makeCommands(),
            plugins: [StubPlugin()],
            isSearchSourceEnabled: { _ in true },
            recentItemIDs: [],
            invokeCommand: { _ in },
            log: QuickLog.palette
        )

        let ids = Set(outcome.items.map(\.id))
        // alpha 声明了空查询入口，beta 没有
        #expect(ids.contains("alpha.go"))
        #expect(!ids.contains("beta.go"), "没有声明 showsWhenQueryEmpty 的命令不该出现在首屏")
        #expect(outcome.timedOutPluginIDs.isEmpty)
    }

    @Test("非空查询按关键词命中")
    func nonEmptyQueryMatchesKeywords() async {
        let outcome = await PaletteSearchEngine.search(
            query: "run",
            staticCommands: makeCommands(),
            plugins: [StubPlugin()],
            isSearchSourceEnabled: { _ in true },
            recentItemIDs: [],
            invokeCommand: { _ in },
            log: QuickLog.palette
        )

        let ids = Set(outcome.items.map(\.id))
        #expect(ids.contains("alpha.go"))
        #expect(ids.contains("beta.go"), "关键词匹配不该受 showsWhenQueryEmpty 影响")
    }

    @Test("无关查询不返回静态命令")
    func unrelatedQueryReturnsNothing() async {
        let outcome = await PaletteSearchEngine.search(
            query: "zzzz-not-a-command",
            staticCommands: makeCommands(),
            plugins: [StubPlugin()],
            isSearchSourceEnabled: { _ in true },
            recentItemIDs: [],
            invokeCommand: { _ in },
            log: QuickLog.palette
        )

        #expect(outcome.items.isEmpty)
    }

    /// 静态命令的快照由 `AppCore.rebuildCommandCatalog()` 过滤后才传进来 ——
    /// 引擎只对动态插件再查一次 `isSearchSourceEnabled`（那些是活对象，开关随时能改）。
    ///
    /// 这条测试锁住的是「引擎不会把快照里的命令再筛一遍」：如果它自作主张过滤，
    /// 快照里的过滤就变成了两处逻辑，改一处忘一处时行为会漂移。
    @Test("静态命令直接用快照，不重复过滤搜索来源")
    func staticCommandsComeFromTheSnapshotAsIs() async {
        let outcome = await PaletteSearchEngine.search(
            query: "run",
            staticCommands: makeCommands(),
            plugins: [],
            isSearchSourceEnabled: { _ in false },
            recentItemIDs: [],
            invokeCommand: { _ in },
            log: QuickLog.palette
        )

        // 快照里有什么就返回什么：过滤是 rebuildCommandCatalog 的职责
        #expect(Set(outcome.items.map(\.id)).count == 2)
    }

    @Test("搜索来源开启时动态插件参与")
    func enabledSourceRunsDynamicPlugin() async {
        let log = CallLog()
        let outcome = await PaletteSearchEngine.search(
            query: "stub",
            staticCommands: [],
            plugins: [StubPlugin(log: log)],
            isSearchSourceEnabled: { _ in true },
            recentItemIDs: [],
            invokeCommand: { _ in },
            log: QuickLog.palette
        )

        #expect(outcome.items.map(\.id) == ["stub.dynamic"])
        #expect(log.callCount("stub") == 1)
    }

    /// 动态插件是活对象，闸门要在每次搜索时现查；关掉来源必须连闸门都不进
    @Test("搜索来源关闭后动态插件不参与")
    func disabledSourceSkipsDynamicPlugin() async {
        let log = CallLog()
        let outcome = await PaletteSearchEngine.search(
            query: "stub",
            staticCommands: [],
            plugins: [StubPlugin(log: log)],
            isSearchSourceEnabled: { _ in false },
            recentItemIDs: [],
            invokeCommand: { _ in },
            log: QuickLog.palette
        )

        #expect(outcome.items.isEmpty, "来源被关掉的插件不该产出动态结果")
        #expect(log.callCount("stub") == 0, "来源被关掉时连 dynamicSearch 都不该被调用")
    }

    @Test("插件自身被禁用时不参与动态搜索")
    func disabledPluginSkipsDynamicSearch() async {
        let log = CallLog()
        let plugin = StubPlugin(log: log)
        plugin.isEnabled = false

        let outcome = await PaletteSearchEngine.search(
            query: "stub",
            staticCommands: [],
            plugins: [plugin],
            isSearchSourceEnabled: { _ in true },
            recentItemIDs: [],
            invokeCommand: { _ in },
            log: QuickLog.palette
        )

        #expect(outcome.items.isEmpty)
        #expect(log.callCount("stub") == 0, "禁用插件连闸门都不该进")
    }

    /// 超时必须报出来，而不是静默变成「没搜到」—— 两者对用户与排查者是不同的事
    @Test("插件超时被记录且取消其工作")
    func hangingPluginTimesOut() async {
        let log = CallLog()
        let outcome = await PaletteSearchEngine.search(
            query: "hang",
            staticCommands: [],
            plugins: [HangingPlugin(log: log)],
            isSearchSourceEnabled: { _ in true },
            recentItemIDs: [],
            invokeCommand: { _ in },
            log: QuickLog.palette,
            pluginTimeout: .milliseconds(50)
        )

        #expect(outcome.items.isEmpty)
        #expect(outcome.timedOutPluginIDs == ["hang"])
        #expect(log.callCount("hang") == 1)
        #expect(
            log.didObserveCancellation("hang"),
            "超时后插件必须收到取消信号，否则它还在占着 CPU 跑一个没人要的查询")
    }

    /// 结果上限必须生效：失控的插件不该把几千条塞进面板
    @Test("结果被截断到上限")
    func resultsAreLimited() async {
        let many = (0..<200).map { i in
            IndexedCommand(
                CommandDescriptor(
                    id: "bulk.\(i)", pluginID: "bulk", pluginName: "Bulk", title: "Bulk \(i)",
                    keywords: ["bulk"], icon: "circle"))
        }
        let outcome = await PaletteSearchEngine.search(
            query: "bulk",
            staticCommands: many,
            plugins: [],
            isSearchSourceEnabled: { _ in true },
            recentItemIDs: [],
            invokeCommand: { _ in },
            log: QuickLog.palette
        )

        #expect(outcome.items.count == PaletteSearchEngine.resultLimit)
    }
}
