// PluginCommandsTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI
import Testing

@testable import QuickCore

/// 守住「默认 commands = 打开本插件 + functionCommands」这条组装规则。
///
/// `functionCommands` 必须**同时**是协议要求 —— 只给扩展默认实现的话，默认 `commands`
/// 会静态派发到空默认，各插件的功能命令会被悄悄丢掉（设置页的「触发关键字」整节消失、
/// 静态命令目录也会缩水）。这个用例就是那条经验的守卫。
@Suite("插件命令组装")
@MainActor
struct PluginCommandsTests {

    private final class FakePlugin: QuickPlugin {
        static let id = "fake"
        static let name = "Fake"
        static let icon = "star"
        var isEnabled = true
        static let triggerWords = ["fake"]
        static var functionCommands: [CommandDescriptor] {
            [
                CommandDescriptor(
                    id: "fake.do", pluginID: id, pluginName: name, title: "做点什么",
                    keywords: ["do"], icon: "star")
            ]
        }
        func makeView() -> AnyView { AnyView(EmptyView()) }
    }

    @Test("默认 commands = 打开本插件 + functionCommands")
    func commandsIncludeFunctionCommands() {
        let ids = FakePlugin.commands.map(\.id)
        #expect(ids.contains(CommandID.openPlugin("fake")))
        #expect(ids.contains("fake.do"), "功能命令被丢掉了 —— functionCommands 可能没走动态派发")
        #expect(FakePlugin.commands.count == 2)
    }

    @Test("没有功能命令时只有「打开本插件」")
    func commandsFallBackToOpenOnly() {
        final class PlainPlugin: QuickPlugin {
            static let id = "plain"
            static let name = "Plain"
            static let icon = "circle"
            var isEnabled = true
            func makeView() -> AnyView { AnyView(EmptyView()) }
        }
        #expect(PlainPlugin.commands.map(\.id) == [CommandID.openPlugin("plain")])
    }
}
