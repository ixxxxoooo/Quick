// PaletteSelectionTests.swift
// Quick — 原生 macOS 效率启动器
// @author ixxxxoooo

import Testing
@testable import QuickUI

@Suite("面板选中状态")
@MainActor
struct PaletteSelectionTests {

    /// 上下键才推进滚动令牌：列表据此做滚动跟随
    @Test("键盘移动会更新滚动令牌")
    func keyboardMoveBumpsScrollToken() {
        let selection = PaletteSelection()
        selection.update(count: 5) { _ in }
        let before = selection.keyboardScrollToken

        #expect(selection.move(1))
        #expect(selection.keyboardScrollToken != before)
    }

    /// 悬停改选中项，但不该让列表滚动 —— 这是「光标扫过第一行会跳一下」的根因
    @Test("悬停选中不动滚动令牌")
    func hoverSelectionKeepsScrollToken() {
        let selection = PaletteSelection()
        selection.update(count: 5) { _ in }
        let before = selection.keyboardScrollToken

        selection.selectByHover(2)

        #expect(selection.index == 2)
        #expect(selection.keyboardScrollToken == before)
    }

    /// 边界处按不出界，令牌仍推进（滚到首尾时贴边是有效动作）
    @Test("边界按键仍消费并推进令牌")
    func boundaryMoveStillBumpsToken() {
        let selection = PaletteSelection()
        selection.update(count: 3) { _ in }

        #expect(selection.move(-1))
        #expect(selection.index == 0)

        let before = selection.keyboardScrollToken
        #expect(selection.move(-1))
        #expect(selection.keyboardScrollToken != before)
    }

    // MARK: - 跳转 / 翻页 / 数字直达

    @Test("跳到首项与末项")
    func jumpToEnds() {
        let selection = PaletteSelection()
        selection.update(count: 20) { _ in }
        #expect(selection.jump(to: .last))
        #expect(selection.index == 19)
        #expect(selection.jump(to: .first))
        #expect(selection.index == 0)
    }

    @Test("没有结果时跳转与翻页都不消费")
    func emptyResultsDoNotConsume() {
        let selection = PaletteSelection()
        selection.update(count: 0) { _ in }
        #expect(!selection.jump(to: .last))
        #expect(!selection.page(1))
        #expect(!selection.activateNumbered(1))
    }

    @Test("翻页按页大小移动并夹在边界内")
    func pageClampsToBounds() {
        let selection = PaletteSelection()
        selection.update(count: 10) { _ in }
        #expect(selection.page(1, pageSize: 4))
        #expect(selection.index == 4)
        #expect(selection.page(1, pageSize: 4))
        #expect(selection.page(1, pageSize: 4))
        #expect(selection.index == 9)
        #expect(selection.page(-1, pageSize: 100))
        #expect(selection.index == 0)
    }

    @Test("⌘数字执行对应行并把选中项挪过去")
    func numberedActivation() {
        let selection = PaletteSelection()
        var activated: [Int] = []
        selection.update(count: 5) { activated.append($0) }
        #expect(selection.activateNumbered(3))
        #expect(activated == [2])
        #expect(selection.index == 2)
    }

    @Test("⌘数字超出结果数或范围时不消费")
    func numberedOutOfRange() {
        let selection = PaletteSelection()
        var activated = 0
        selection.update(count: 3) { _ in activated += 1 }
        #expect(!selection.activateNumbered(4))
        #expect(!selection.activateNumbered(0))
        #expect(!selection.activateNumbered(10))
        #expect(activated == 0)
    }
}
