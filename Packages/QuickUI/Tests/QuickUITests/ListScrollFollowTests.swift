// ListScrollFollowTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI
import Testing
@testable import QuickUI

@Suite("列表滚动跟随")
struct ListScrollFollowTests {

    /// 中间项不滚：这是「不要在中间就滚动」的那条规则本身
    @Test("中间项交给最小幅度滚动")
    func middleItemsUseMinimalScroll() {
        for index in 1..<9 {
            #expect(ListScrollFollow.anchor(for: index, count: 10) == nil)
        }
    }

    /// 两端给明确锚点
    @Test("首项贴顶、末项贴底")
    func edgesUseExplicitAnchors() {
        #expect(ListScrollFollow.anchor(for: 0, count: 10) == .top)
        #expect(ListScrollFollow.anchor(for: 9, count: 10) == .bottom)
    }

    /// 只有一项时首项优先：它既是第一项也是最后一项，贴顶才不会在只有一屏内容时乱跳
    @Test("单项列表按首项处理")
    func singleItemTreatedAsFirst() {
        #expect(ListScrollFollow.anchor(for: 0, count: 1) == .top)
    }

    /// 两项列表两端各自成立，中间没有空隙
    @Test("两项列表两端都成立")
    func twoItemList() {
        #expect(ListScrollFollow.anchor(for: 0, count: 2) == .top)
        #expect(ListScrollFollow.anchor(for: 1, count: 2) == .bottom)
    }

    /// 越界不该崩，也不该给一个会滚出列表的锚点
    @Test("越界下标不产生滚动")
    func outOfRangeIndexIsSafe() {
        #expect(ListScrollFollow.anchor(for: 5, count: 0) == nil)
        #expect(ListScrollFollow.anchor(for: -1, count: 10) == nil)
    }
}
