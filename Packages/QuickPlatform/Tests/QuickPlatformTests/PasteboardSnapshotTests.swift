// PasteboardSnapshotTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation
import Testing

@testable import QuickPlatform

@Suite("剪贴板快照")
struct PasteboardSnapshotTests {

    /// 用独立命名的私有剪贴板：不去动用户的通用剪贴板，用例之间也互不干扰
    private func makeBoard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("quick.test.snapshot.\(UUID().uuidString)"))
    }

    @Test("恢复后字符串与二进制类型都回来")
    func restoresAllTypes() {
        let board = makeBoard()
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString("原文", forType: .string)
        item.setData(Data([1, 2, 3]), forType: .png)
        board.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(board)
        board.clearContents()
        board.setString("替换结果", forType: .string)

        snapshot.restore(onto: board)
        #expect(board.string(forType: .string) == "原文")
        #expect(board.data(forType: .png) == Data([1, 2, 3]))
    }

    @Test("空剪贴板的快照恢复后仍是空")
    func emptySnapshotRestoresToEmpty() {
        let board = makeBoard()
        board.clearContents()

        let snapshot = PasteboardSnapshot.capture(board)
        board.setString("替换结果", forType: .string)

        snapshot.restore(onto: board)
        #expect(board.string(forType: .string) == nil)
    }

    @Test("capture(from:) 与 capture(_:) 行为一致")
    func captureFromAlias() {
        let board = makeBoard()
        board.clearContents()
        board.setString("别名测试", forType: .string)

        let viaUnderscore = PasteboardSnapshot.capture(board)
        board.clearContents()
        board.setString("别名测试", forType: .string)
        let viaFrom = PasteboardSnapshot.capture(from: board)

        board.clearContents()
        viaUnderscore.restore(onto: board)
        #expect(board.string(forType: .string) == "别名测试")

        board.clearContents()
        viaFrom.restore(onto: board)
        #expect(board.string(forType: .string) == "别名测试")
    }
}
