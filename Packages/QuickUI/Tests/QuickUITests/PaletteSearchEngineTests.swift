// PaletteSearchEngineTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickUI
import QuickCore

/// 空查询时每个插件露一条入口，非空时按关键词打分
private final class StubPlugin: QuickPlugin {
    static let id = "stub"
    static let name = "Stub"
    static let icon = "circle"
    static let triggerWords = ["stub"]
    static let functionCommands = [
        CommandDescriptor(
            id: "stub.open-thing", pluginID: id, pluginName: name, title: "打开东西",
            keywords: ["thing"], icon: "circle",
            // 空查询时它是该插件露出的那一条
            showsWhenQueryEmpty: true)
    ]
    var isEnabled = true
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
    /// 引擎只对**动态插件**再查一次 `isSearchSourceEnabled`（那些是活对象，开关随时能改）。
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

    /// 动态插件相反：它们是活对象，闸门要在每次搜索时现查
    @Test("搜索来源关闭后动态插件不参与")
    func disabledSourceSkipsDynamicPlugin() async {
        let outcome = await PaletteSearchEngine.search(
            query: "stub",
            staticCommands: [],
            plugins: [StubPlugin()],
            isSearchSourceEnabled: { _ in false },
            recentItemIDs: [],
            invokeCommand: { _ in },
            log: QuickLog.palette
        )

        #expect(outcome.items.isEmpty, "来源被关掉的插件不该产出动态结果")
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
