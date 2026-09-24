// AIWebViewWindowTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
import Testing

@testable import PluginAI

/// AI 窗口的窗口配置
///
/// 「能不能在 ⌘Tab / Mission Control 里被找回来」全部由这几个参数决定 —— 它们平时藏在
/// 建窗口那条会连网加载页面的路上，所以单独抽了 `makePanel` 出来钉住。
@Suite("AI 窗口配置")
@MainActor
struct AIWebViewWindowTests {

    private func makePanel() throws -> AIWebViewPanel {
        let provider = try #require(AIProviderRegistry.provider(for: "deepseek"))
        return AIWebViewWindowManager.makePanel(
            provider: provider,
            size: NSSize(width: 800, height: 600)
        )
    }

    /// 非激活面板不参与应用激活时的窗口排序，也就不会出现在 ⌘Tab / Mission Control 里
    @Test("不是非激活面板")
    func isNotNonactivatingPanel() throws {
        let panel = try makePanel()
        #expect(panel.styleMask.contains(.nonactivatingPanel) == false)
    }

    @Test("是普通窗口：能成为 key，也能成为 main")
    func canBecomeKeyAndMain() throws {
        let panel = try makePanel()
        #expect(panel.canBecomeKey)
        #expect(panel.canBecomeMain)
    }

    /// 切到别的应用时窗口要留在屏幕上，切回来才找得到它
    @Test("失活时不隐藏")
    func staysVisibleWhenInactive() throws {
        let panel = try makePanel()
        #expect(panel.hidesOnDeactivate == false)
    }

    @Test("窗口标识带着 Provider id")
    func identifierCarriesProviderID() throws {
        let panel = try makePanel()
        #expect(panel.identifier?.rawValue == "quick.ai.deepseek")
    }

    @Test("标题就是 Provider 显示名")
    func titleIsProviderName() throws {
        let panel = try makePanel()
        #expect(panel.title == "DeepSeek")
    }

    /// 主菜单刻意不放 ⌘W（留给主面板），所以这个普通窗口得自己接住它。
    /// ⌘W 走 `performClose` → `close()` → 隐藏，与点红绿灯一致。
    @Test("⌘W 被接住并触发关闭回调")
    func commandWCloses() throws {
        let panel = try makePanel()
        var closed = 0
        panel.onClose = { closed += 1 }

        guard
            let commandW = Self.keyDown(
                keyCode: kVK_ANSI_W, modifiers: .command, characters: "w")
        else {
            Issue.record("无法构造合成按键事件")
            return
        }

        #expect(panel.performKeyEquivalent(with: commandW))
        #expect(closed == 1)
    }

    /// 其余按键必须放行，否则窗口会吃掉所有键盘输入
    @Test("普通按键不被窗口消费")
    func otherKeysFallThrough() throws {
        let panel = try makePanel()
        guard
            let commandR = Self.keyDown(
                keyCode: kVK_ANSI_R, modifiers: .command, characters: "r")
        else {
            Issue.record("无法构造合成按键事件")
            return
        }
        #expect(panel.performKeyEquivalent(with: commandR) == false)
    }

    /// 合成一个按下事件（返回 nil 时由调用方记一条失败，而不是崩掉）
    private static func keyDown(
        keyCode: Int,
        modifiers: NSEvent.ModifierFlags,
        characters: String
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )
    }
}
