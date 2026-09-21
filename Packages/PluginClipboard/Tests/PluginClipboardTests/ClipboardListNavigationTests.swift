// ClipboardListNavigationTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import PluginClipboard

@Suite("剪贴板列表导航")
struct ClipboardListNavigationTests {

    @Test("中间正常走一格")
    func stepsInTheMiddle() {
        #expect(ClipboardListNavigation.step(from: 0, direction: 1, count: 5) == 1)
        #expect(ClipboardListNavigation.step(from: 3, direction: -1, count: 5) == 2)
    }

    @Test("两端夹住，不回绕")
    func clampsAtBothEnds() {
        #expect(ClipboardListNavigation.step(from: 0, direction: -1, count: 5) == 0)
        #expect(ClipboardListNavigation.step(from: 4, direction: 1, count: 5) == 4)
    }

    /// 回归测试：列表比下标短时必须还能动
    ///
    /// 面板开着删掉一条、或者历史被裁剪之后，下标会停在界外。旧实现算出的新下标仍落在界外，
    /// 于是一连按几下都「一点不动」。
    @Test("下标越界时也能动起来")
    func recoversFromStaleIndex() {
        // 停在 7，列表只剩 3 条：往上应该直接落到有效范围内
        #expect(ClipboardListNavigation.step(from: 7, direction: -1, count: 3) == 1)
        // 往下同样要落到最后一条，而不是原地不动
        #expect(ClipboardListNavigation.step(from: 7, direction: 1, count: 3) == 2)
    }

    @Test("空列表不动")
    func emptyListStaysAtZero() {
        #expect(ClipboardListNavigation.step(from: 3, direction: 1, count: 0) == 0)
        #expect(ClipboardListNavigation.step(from: 3, direction: -1, count: 0) == 0)
        #expect(ClipboardListNavigation.clamp(3, count: 0) == 0)
    }

    @Test("夹取把任意下标拉回范围内")
    func clampPullsIntoRange() {
        #expect(ClipboardListNavigation.clamp(9, count: 3) == 2)
        #expect(ClipboardListNavigation.clamp(-4, count: 3) == 0)
        #expect(ClipboardListNavigation.clamp(1, count: 3) == 1)
    }

    /// 夹取之后**下标必须落在列表里**：否则下一次上下键又会原地不动
    @Test("夹取结果永远指向存在的条目")
    func clampAlwaysLandsOnAnEntry() {
        for count in 1...6 {
            for index in -3...(count + 3) {
                let clamped = ClipboardListNavigation.clamp(index, count: count)
                #expect((0..<count).contains(clamped))
            }
        }
    }
}
