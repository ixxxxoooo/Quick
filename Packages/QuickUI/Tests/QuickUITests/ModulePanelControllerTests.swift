// ModulePanelControllerTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI
import Testing
@testable import QuickUI

@MainActor
@Suite("ModulePanelController 分离窗口")
struct ModulePanelControllerTests {

    @Test("初始状态无分离窗口")
    func initialStateEmpty() {
        let controller = ModulePanelController()
        #expect(controller.focusIfOpen("devtools") == false)
    }

    @Test("分离创建独立窗口")
    func detachCreatesWindow() {
        let controller = ModulePanelController()
        let view = AnyView(Text("测试工具"))

        controller.detach(
            moduleID: "devtools",
            moduleName: "开发工具",
            icon: "wrench.and.screwdriver",
            view: view,
            sourceWindow: nil
        )

        #expect(controller.focusIfOpen("devtools") == true)

        controller.closeAll()
    }

    @Test("单例策略：同一模块不重复创建窗口")
    func singletonPreventsDoubleCreate() {
        let controller = ModulePanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            moduleID: "clipboard",
            moduleName: "剪贴板",
            icon: "doc.on.clipboard",
            view: view,
            sourceWindow: nil
        )

        controller.detach(
            moduleID: "clipboard",
            moduleName: "剪贴板",
            icon: "doc.on.clipboard",
            view: view,
            sourceWindow: nil
        )

        #expect(controller.focusIfOpen("clipboard") == true)

        controller.closeAll()
    }

    @Test("close 关闭指定模块窗口")
    func closeRemovesWindow() {
        let controller = ModulePanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            moduleID: "ai",
            moduleName: "AI",
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
        let controller = ModulePanelController()
        let view = AnyView(Text("测试"))

        controller.detach(moduleID: "a", moduleName: "A", icon: "a.circle", view: view, sourceWindow: nil)
        controller.detach(moduleID: "b", moduleName: "B", icon: "b.circle", view: view, sourceWindow: nil)

        #expect(controller.focusIfOpen("a") == true)
        #expect(controller.focusIfOpen("b") == true)

        controller.closeAll()

        #expect(controller.focusIfOpen("a") == false)
        #expect(controller.focusIfOpen("b") == false)
    }

    @Test("分离窗口有最小尺寸约束")
    func detachedWindowHasMinSize() {
        let controller = ModulePanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            moduleID: "test-min",
            moduleName: "Test",
            icon: "gear",
            view: view,
            sourceWindow: nil
        )

        #expect(DesignTokens.Size.detachedPanelMinWidth > 0)
        #expect(DesignTokens.Size.detachedPanelMinHeight > 0)

        controller.closeAll()
    }
}
