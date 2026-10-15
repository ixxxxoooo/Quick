// AIChatShortcutTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import QuickUI

@Suite("AIChatShortcut 键位")
struct AIChatShortcutTests {

    private func resolve(
        _ characters: String?, keyCode: Int = 0, shift: Bool = false, option: Bool = false,
        control: Bool = false, command: Bool = true
    ) -> AIChatShortcut? {
        AIChatShortcut.resolve(
            characters: characters, keyCode: keyCode, command: command, shift: shift,
            option: option, control: control)
    }

    @Test("⌘ 组合键映射到动作")
    func commandKeys() {
        #expect(resolve("n") == .newChat)
        #expect(resolve("[") == .previousSession)
        #expect(resolve("]") == .nextSession)
        #expect(resolve("b") == .toggleSidebar)
        #expect(resolve("f") == .focusFilter)
        #expect(resolve("r") == .regenerate)
        #expect(resolve("e") == .renameSession)
        #expect(resolve("N") == .newChat)
    }

    @Test("⌘⇧ 组合")
    func shifted() {
        #expect(resolve("c", shift: true) == .copyLastReply)
        #expect(resolve("p", shift: true) == .togglePin)
        #expect(resolve("n", shift: true) == nil)
    }

    @Test("⌘⌫ 是删除会话，⌘⇧⌫ 不是")
    func backspace() {
        #expect(resolve(nil, keyCode: 51) == .deleteSession)
        #expect(resolve(nil, keyCode: 51, shift: true) == nil)
    }

    @Test("没按 ⌘、或带着 ⌥ / ⌃ 都不算")
    func requiresPlainCommand() {
        #expect(resolve("n", command: false) == nil)
        #expect(resolve("n", option: true) == nil)
        #expect(resolve("n", control: true) == nil)
    }

    @Test("其他按键返回 nil（⌘C / ⌘V 留给文本编辑）")
    func unrelated() {
        #expect(resolve("c") == nil)
        #expect(resolve("v") == nil)
        #expect(resolve(nil) == nil)
        #expect(resolve("nn") == nil)
    }
}
