// RecentPromotionTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickUI
import QuickCore

@Suite("首屏按最近使用重排")
@MainActor
struct RecentPromotionTests {

    private func item(_ id: String, relevance: Double = 0.5) -> SearchableItem {
        SearchableItem(
            id: id, pluginID: "test", title: id, icon: "circle",
            relevance: relevance, action: {})
    }

    @Test("最近使用过的排到最前，且按时间顺序")
    func promotesRecentsInOrder() {
        let items = [item("a"), item("b"), item("c"), item("d")]
        // c 最近用过、然后是 a
        let promoted = PaletteSearchEngine.promotingRecents(items, recents: ["c", "a"])

        #expect(promoted.map(\.id) == ["c", "a", "b", "d"])
    }

    @Test("其余条目保持原顺序")
    func keepsRemainingOrder() {
        let items = [item("a"), item("b"), item("c")]
        let promoted = PaletteSearchEngine.promotingRecents(items, recents: ["c"])
        #expect(promoted.map(\.id) == ["c", "a", "b"])
    }

    @Test("没有历史时原样返回")
    func noRecentsIsNoop() {
        let items = [item("a"), item("b")]
        #expect(PaletteSearchEngine.promotingRecents(items, recents: []).map(\.id) == ["a", "b"])
    }

    @Test("历史里有已经不存在的 id 时不受影响")
    func ignoresUnknownRecentIDs() {
        // 卸载了一个应用、删掉了一个插件：它的 id 还躺在历史里
        let items = [item("a"), item("b")]
        let promoted = PaletteSearchEngine.promotingRecents(items, recents: ["gone", "b"])
        #expect(promoted.map(\.id) == ["b", "a"])
    }

    @Test("不丢条目也不重复")
    func preservesCount() {
        let items = (0..<20).map { item("item-\($0)") }
        let promoted = PaletteSearchEngine.promotingRecents(items, recents: ["item-7", "item-19", "item-3"])
        #expect(promoted.count == 20)
        #expect(Set(promoted.map(\.id)).count == 20)
    }
}
