// TextDiffPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginTextDiff

@Suite("文本对比逻辑")
struct TextDiffLogicTests {

    @Test("完全相同的输入没有差异")
    func identicalInputsHaveNoDifferences() {
        let result = TextDiffLogic.diff("a\nb", against: "a\nb")

        #expect(result.lines.map(\.type) == [.same, .same])
        #expect(result.lines.map(\.text) == ["a", "b"])
        #expect(result.addedCount == 0)
        #expect(result.removedCount == 0)
    }

    @Test("纯新增一行")
    func pureInsertion() {
        let result = TextDiffLogic.diff("a", against: "a\nb")

        #expect(result.lines.map(\.type) == [.same, .added])
        #expect(result.lines.map(\.text) == ["a", "b"])
        #expect(result.addedCount == 1)
        #expect(result.removedCount == 0)
    }

    @Test("纯删除一行")
    func pureDeletion() {
        let result = TextDiffLogic.diff("a\nb", against: "a")

        #expect(result.lines.map(\.type) == [.same, .removed])
        #expect(result.lines.map(\.text) == ["a", "b"])
        #expect(result.addedCount == 0)
        #expect(result.removedCount == 1)
    }

    @Test("同一行被改写时先记删除再记新增")
    func changedLineReportsRemovedThenAdded() {
        let result = TextDiffLogic.diff("a\nold", against: "a\nnew")

        #expect(result.lines.map(\.type) == [.same, .removed, .added])
        #expect(result.lines.map(\.text) == ["a", "old", "new"])
        #expect(result.addedCount == 1)
        #expect(result.removedCount == 1)
    }

    @Test("对比是按下标对齐的，中间插入会让后续行全部错位")
    func comparisonIsIndexAligned() {
        // 这是原有算法：不做 LCS 重排，插入一行会让原来的第 2 行显示为「被改写」
        let result = TextDiffLogic.diff("a\nb", against: "a\nx\nb")

        #expect(result.lines.map(\.type) == [.same, .removed, .added, .added])
        #expect(result.lines.map(\.text) == ["a", "b", "x", "b"])
        #expect(result.addedCount == 2)
        #expect(result.removedCount == 1)
    }

    @Test("空文本与空文本仍产生一行空的 same")
    func bothEmptyYieldsOneEmptySameLine() {
        // components(separatedBy:) 对空串返回 [""]，所以「都为空」不是「零行差异」
        let result = TextDiffLogic.diff("", against: "")

        #expect(result.lines.count == 1)
        #expect(result.lines.first?.type == .same)
        #expect(result.lines.first?.text == "")
        #expect(result.addedCount == 0)
        #expect(result.removedCount == 0)
    }

    @Test("空文本与非空文本：空行记删除，内容记新增")
    func emptyVersusNonEmpty() {
        // 空串被当成长度为 1 的空行，于是「无到有」也被记成一次删除加一次新增
        let result = TextDiffLogic.diff("", against: "x")

        #expect(result.lines.map(\.type) == [.removed, .added])
        #expect(result.lines.map(\.text) == ["", "x"])
        #expect(result.addedCount == 1)
        #expect(result.removedCount == 1)
    }

    @Test("多行纯新增")
    func multipleLinesInserted() {
        let result = TextDiffLogic.diff("a", against: "a\nb\nc")

        #expect(result.lines.map(\.type) == [.same, .added, .added])
        #expect(result.addedCount == 2)
        #expect(result.removedCount == 0)
    }

    @Test("两边都为空行时算作相同")
    func blankLineVersusBlankLine() {
        let result = TextDiffLogic.diff("a\n\nb", against: "a\n\nb")

        #expect(result.lines.map(\.type) == [.same, .same, .same])
        #expect(result.addedCount == 0)
        #expect(result.removedCount == 0)
    }

    @Test("前缀符号")
    func linePrefixes() {
        #expect(TextDiffLogic.linePrefix(.same) == " ")
        #expect(TextDiffLogic.linePrefix(.added) == "+")
        #expect(TextDiffLogic.linePrefix(.removed) == "-")
    }

    @Test("渲染成可复制文本时带前缀")
    func renderingAddsPrefixes() {
        let result = TextDiffLogic.diff("a", against: "b")
        #expect(TextDiffLogic.render(result.lines) == "-a\n+b")
    }

    @Test("DiffLine 的相等只看文本与类型，不看列表身份")
    func diffLineEqualityIgnoresIdentity() {
        let first = TextDiffLogic.DiffLine(text: "a", type: .same)
        let second = TextDiffLogic.DiffLine(text: "a", type: .same)
        let third = TextDiffLogic.DiffLine(text: "a", type: .added)

        #expect(first.id != second.id)
        #expect(first == second)
        #expect(first != third)
    }

    // MARK: - 逐行状态（编辑器逐行上色用）

    @Test("相同行两侧都是 same")
    func sideLineStatesSame() {
        let states = TextDiffLogic.sideLineStates("a\nb", against: "a\nb")
        #expect(states.left == [.same, .same])
        #expect(states.right == [.same, .same])
    }

    @Test("改写行：原文记 removed，修改后记 added")
    func sideLineStatesChanged() {
        let states = TextDiffLogic.sideLineStates("a\nold", against: "a\nnew")
        #expect(states.left == [.same, .removed])
        #expect(states.right == [.same, .added])
    }

    @Test("纯新增只给右侧记 added")
    func sideLineStatesInsertion() {
        let states = TextDiffLogic.sideLineStates("a", against: "a\nb")
        #expect(states.left == [.same])
        #expect(states.right == [.same, .added])
    }

    @Test("纯删除只给左侧记 removed")
    func sideLineStatesDeletion() {
        let states = TextDiffLogic.sideLineStates("a\nb", against: "a")
        #expect(states.left == [.same, .removed])
        #expect(states.right == [.same])
    }

    @Test("状态数量分别等于两侧行数")
    func sideLineStatesCountPerSide() {
        // 中间插入后按下标对齐，后续行全部错位（既有行为）；状态数量仍各算各的
        let states = TextDiffLogic.sideLineStates("a\nb", against: "a\nx\nb")
        #expect(states.left.count == 2)
        #expect(states.right.count == 3)
    }
}

@Suite("文本对比插件契约")
@MainActor
struct TextDiffPluginTests {

    @Test("插件 id 是 kebab-case 且与约定一致")
    func identifierIsKebabCase() {
        let id = TextDiffPlugin.id
        #expect(id == "text-diff")
        #expect(id == id.lowercased())
        #expect(id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        #expect(!id.hasPrefix("-") && !id.hasSuffix("-"))
    }

    @Test("名称、图标、触发词都不为空")
    func metadataIsPresent() {
        #expect(!TextDiffPlugin.name.isEmpty)
        #expect(!TextDiffPlugin.icon.isEmpty)
        #expect(!TextDiffPlugin.triggerWords.isEmpty)
    }

    @Test("命中触发词时只返回一条结果")
    func triggerReturnsExactlyOneItem() async {
        let plugin = TextDiffPlugin()
        let results = await plugin.searchItems(query: "对比")

        #expect(results.count == 1)
        #expect(results.first?.pluginID == TextDiffPlugin.id)
        #expect(results.first?.icon == TextDiffPlugin.icon)
    }

    @Test("不命中触发词时返回空")
    func unrelatedQueryReturnsNothing() async {
        let plugin = TextDiffPlugin()
        #expect(await plugin.searchItems(query: "zzzz").isEmpty)
    }
}
