// AIWebViewWindowTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
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
}
