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
}
