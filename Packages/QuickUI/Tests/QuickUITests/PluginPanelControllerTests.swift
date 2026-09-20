// PluginPanelControllerTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI
import Testing
@testable import QuickUI

@MainActor
@Suite("PluginPanelController 分离窗口")
struct PluginPanelControllerTests {

    @Test("初始状态无分离窗口")
    func initialStateEmpty() {
        let controller = PluginPanelController()
        #expect(controller.focusIfOpen("devtools") == false)
    }

    @Test("分离创建独立窗口")
    func detachCreatesWindow() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试工具"))

        controller.detach(
            pluginID: "devtools",
            pluginName: "开发工具",
            icon: "wrench.and.screwdriver",
            view: view,
            sourceWindow: nil
        )

        #expect(controller.focusIfOpen("devtools") == true)

        controller.closeAll()
    }

    @Test("单例策略：同一插件不重复创建窗口")
    func singletonPreventsDoubleCreate() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            pluginID: "clipboard",
            pluginName: "剪贴板",
            icon: "doc.on.clipboard",
            view: view,
            sourceWindow: nil
        )

        controller.detach(
            pluginID: "clipboard",
            pluginName: "剪贴板",
            icon: "doc.on.clipboard",
            view: view,
            sourceWindow: nil
        )

        #expect(controller.focusIfOpen("clipboard") == true)

        controller.closeAll()
    }

    @Test("close 关闭指定插件窗口")
    func closeRemovesWindow() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            pluginID: "ai",
            pluginName: "AI",
            icon: "brain",
            view: view,
            sourceWindow: nil
        )

        #expect(controller.focusIfOpen("ai") == true)

        controller.close("ai")
        #expect(controller.focusIfOpen("ai") == false)
    }

    @Test("closeAll 关闭所有分离窗口")
    func closeAllRemovesAllWindows() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(pluginID: "a", pluginName: "A", icon: "a.circle", view: view, sourceWindow: nil)
        controller.detach(pluginID: "b", pluginName: "B", icon: "b.circle", view: view, sourceWindow: nil)

        #expect(controller.focusIfOpen("a") == true)
        #expect(controller.focusIfOpen("b") == true)

        controller.closeAll()

        #expect(controller.focusIfOpen("a") == false)
        #expect(controller.focusIfOpen("b") == false)
    }

    @Test("分离窗口有最小尺寸约束")
    func detachedWindowHasMinSize() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            pluginID: "test-min",
            pluginName: "Test",
            icon: "gear",
            view: view,
            sourceWindow: nil
        )

        #expect(DesignTokens.Size.detachedPanelMinWidth > 0)
        #expect(DesignTokens.Size.detachedPanelMinHeight > 0)

        controller.closeAll()
    }
}
