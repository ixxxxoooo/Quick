// ConfirmDialogTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import Testing

@testable import QuickUI

@Suite("模态确认框")
@MainActor
struct ConfirmDialogTests {

    @Test("回车确认、Esc 取消、方向键一律吞掉")
    func keyMapping() {
        #expect(ConfirmDialogKey.resolve(.submit) == .confirm)
        #expect(ConfirmDialogKey.resolve(.cancel) == .cancel)
        #expect(ConfirmDialogKey.resolve(.move(1)) == .ignore)
        #expect(ConfirmDialogKey.resolve(.move(-1)) == .ignore)
        #expect(ConfirmDialogKey.resolve(.tab(1)) == .ignore)
    }

    @Test("插件声明 wantsCancel 后 Esc 变成 cancel 请求，且 reset 会清掉它")
    func cancelRoutingState() {
        let search = PluginSearchQuery()
        #expect(!search.wantsCancel)

        search.wantsCancel = true
        search.request(.cancel)
        #expect(search.lastCommand == .cancel)

        search.reset()
        #expect(!search.wantsCancel, "离开插件时必须清掉，否则下一个插件的 Esc 会失灵")
        #expect(search.lastCommand == nil)
    }

    @Test("请求的相等性只看字段，破坏性默认为真")
    func requestDefaults() {
        let a = ConfirmRequest(id: "x", title: "t", message: "m", confirmTitle: "c")
        #expect(a.isDestructive)
        #expect(a == ConfirmRequest(id: "x", title: "t", message: "m", confirmTitle: "c"))
    }
}
