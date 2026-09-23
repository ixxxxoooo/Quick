// SelectionCaptureTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Testing

@testable import QuickPlatform

@Suite("选区抓取的剪贴板备份")
struct SelectionCaptureTests {

    /// 备份/恢复必须保住非文本类型
    ///
    /// 旧实现只备份 `string(forType:)`，恢复时 clearContents 之后只写回文本 ——
    /// 用户剪贴板里若是图片或文件，就被这次抓取静默清掉了。
    ///
    /// 测试读写真实 `NSPasteboard.general`：跑之前先备份用户原内容，跑完恢复。
    @Test("含 png + string 的剪贴板，备份/恢复后两种类型都还在")
    func snapshotPreservesNonTextTypes() {
        let board = NSPasteboard.general
        let saved = PasteboardSnapshot.capture(from: board)
        defer { saved.restore(onto: board) }

        // PNG 魔数就够：剪贴板只是存取 data，不校验图片内容
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        board.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString("同时存在的文本", forType: .string)
        board.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(from: board)
        board.clearContents()
        #expect(board.data(forType: .png) == nil, "clearContents 之后类型应当真的没了")
        snapshot.restore(onto: board)

        #expect(board.data(forType: .png) == png)
        #expect(board.string(forType: .string) == "同时存在的文本")
    }
}
