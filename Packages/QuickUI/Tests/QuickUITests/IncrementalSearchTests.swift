// IncrementalSearchTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation
import Testing

import QuickCore
import QuickPlatform
@testable import QuickUI

/// 立刻返回一条结果的插件
private final class FastPlugin: QuickPlugin {
    static let id = "fast"
    static let name = "Fast"
    static let icon = "bolt"
    static let triggerWords = ["q"]
    var isEnabled = true

    nonisolated func accepts(query: String) -> Bool { true }

    nonisolated func dynamicSearch(query: String) async -> [SearchableItem] {
        [SearchableItem(id: "fast.1", pluginID: Self.id, title: "快结果", icon: "bolt", action: {})]
    }
}

/// 过一会儿才返回的插件
private final class SlowPlugin: QuickPlugin {
    static let id = "slow"
    static let name = "Slow"
    static let icon = "tortoise"
    static let triggerWords = ["q"]
    var isEnabled = true

    nonisolated func accepts(query: String) -> Bool { true }

    nonisolated func dynamicSearch(query: String) async -> [SearchableItem] {
        try? await Task.sleep(for: .milliseconds(150))
        return [SearchableItem(id: "slow.1", pluginID: Self.id, title: "慢结果", icon: "tortoise", action: {})]
    }
}

@MainActor
private final class PartialRecorder {
    var snapshots: [[String]] = []
}

@Suite("搜索：增量合并与列表渲染开销")
@MainActor
struct IncrementalSearchTests {

    private func item(_ id: String, relevance: Double = 0.5, plugin: String = "p") -> SearchableItem {
        SearchableItem(
            id: id, pluginID: plugin, pluginName: nil, title: id, subtitle: nil,
            icon: "circle", relevance: relevance, action: {})
    }

    @Test("慢来源未返回时，已完成的来源先以增量结果交出")
    func partialDeliveredBeforeSlowSource() async {
        let recorder = PartialRecorder()
        let outcome = await PaletteSearchEngine.search(
            query: "q",
            staticCommands: [],
            plugins: [FastPlugin(), SlowPlugin()],
            isSearchSourceEnabled: { _ in true },
            recentItemIDs: [],
            invokeCommand: { _ in },
            log: QuickLog.palette,
            progress: { recorder.snapshots.append($0.items.map(\.id)) }
        )

        #expect(recorder.snapshots == [["fast.1"]], "快来源完成后应先交出，且慢来源的结果此时还不在里面")
        #expect(Set(outcome.items.map(\.id)) == ["fast.1", "slow.1"], "最终结果必须包含全部来源")
    }

    @Test("只有一个来源时没有增量回调，结果只走返回值")
    func singleSourceHasNoPartial() async {
        let recorder = PartialRecorder()
        let outcome = await PaletteSearchEngine.search(
            query: "q",
            staticCommands: [],
            plugins: [FastPlugin()],
            isSearchSourceEnabled: { _ in true },
            recentItemIDs: [],
            invokeCommand: { _ in },
            log: QuickLog.palette,
            progress: { recorder.snapshots.append($0.items.map(\.id)) }
        )

        #expect(recorder.snapshots.isEmpty)
        #expect(outcome.items.map(\.id) == ["fast.1"])
    }

    @Test("merged 去重、按相关度排序并限流，与最终结果同一条路径")
    func mergedDedupesSortsAndLimits() {
        let merged = PaletteSearchEngine.merged(
            [item("a", relevance: 0.2), item("b", relevance: 0.9), item("a", relevance: 0.8)],
            isEmptyQuery: false, recents: [])
        #expect(merged.map(\.id) == ["b", "a"], "重复 id 只留先出现的一条，其余按相关度降序")

        let many = (0..<200).map { item("i\($0)", plugin: "p\($0)") }
        #expect(
            PaletteSearchEngine.merged(many, isEmptyQuery: false, recents: []).count
                == PaletteSearchEngine.resultLimit)
    }

    @Test("结果行只在可见输入变化时才算不相等")
    func rowEqualityTracksRenderedInputsOnly() {
        let base = ResultRowView(item: item("x"), isSelected: false, isHovered: false)
        // 同样的内容、不同的闭包：必须相等，否则 .equatable() 永远不生效
        let sameContent = ResultRowView(item: item("x"), isSelected: false, isHovered: false)
        #expect(base == sameContent)
        #expect(base != ResultRowView(item: item("x"), isSelected: true, isHovered: false))
        #expect(base != ResultRowView(item: item("x"), isSelected: false, isHovered: true))
        #expect(base != ResultRowView(item: item("x"), isSelected: false, isHovered: false, query: "x"))
        #expect(base != ResultRowView(item: item("y"), isSelected: false, isHovered: false))
        #expect(base != ResultRowView(item: item("x"), isSelected: false, isHovered: false, quickNumber: 1))
    }

    @Test("高亮缓存：相同输入命中缓存，容量到顶后整体清空")
    func highlightCacheHitsAndEvicts() {
        HighlightCache.reset()
        _ = HighlightCache.attributed(title: "Visual Studio Code", query: "vsc")
        _ = HighlightCache.attributed(title: "Visual Studio Code", query: "vsc")
        #expect(HighlightCache.count == 1)

        // 空查询不进缓存
        _ = HighlightCache.attributed(title: "Safari", query: "")
        #expect(HighlightCache.count == 1)

        for i in 0..<HighlightCache.capacity {
            _ = HighlightCache.attributed(title: "标题\(i)", query: "标")
        }
        #expect(HighlightCache.count <= HighlightCache.capacity)
        HighlightCache.reset()
    }

    @Test("异步加载图标后进入缓存，再次读取命中同一份")
    func asyncIconLoadPopulatesCache() async throws {
        let cache = IconCache()
        let path = "/System/Applications/Calculator.app"
        #expect(cache.cachedIcon(forBundlePath: path) == nil)
        let loaded = try #require(await cache.loadIcon(forBundlePath: path))
        #expect(cache.cachedIcon(forBundlePath: path) === loaded)
        #expect(await cache.loadIcon(forBundlePath: path) === loaded)
    }
}
