// PaletteModeTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing
@testable import QuickUI

@MainActor
@Suite("PaletteMode 模式切换")
struct PaletteModeTests {

    @Test("初始状态为搜索模式")
    func initialStateIsSearchMode() {
        let mode = PaletteMode()
        #expect(mode.activePluginID == nil)
        #expect(mode.isPluginMode == false)
        #expect(mode.context.isEmpty)
        #expect(mode.activePluginName == nil)
        #expect(mode.activePluginIcon == nil)
    }

    @Test("navigate 切换到插件模式")
    func navigateToPlugin() {
        let mode = PaletteMode()
        mode.navigate(to: "devtools", name: "开发工具", icon: "wrench.and.screwdriver", context: ["tool": "json"])

        #expect(mode.activePluginID == "devtools")
        #expect(mode.isPluginMode == true)
        #expect(mode.activePluginName == "开发工具")
        #expect(mode.activePluginIcon == "wrench.and.screwdriver")
        #expect(mode.context["tool"] == "json")
    }

    @Test("popToRoot 返回搜索模式")
    func popToRootClearsState() {
        let mode = PaletteMode()
        mode.navigate(to: "clipboard", name: "剪贴板", icon: "doc.on.clipboard")

        #expect(mode.isPluginMode == true)

        mode.popToRoot()

        #expect(mode.activePluginID == nil)
        #expect(mode.isPluginMode == false)
        #expect(mode.activePluginName == nil)
        #expect(mode.activePluginIcon == nil)
        #expect(mode.context.isEmpty)
    }

    @Test("多次 navigate 切换插件")
    func switchBetweenPlugins() {
        let mode = PaletteMode()

        mode.navigate(to: "devtools", name: "开发工具", icon: "wrench.and.screwdriver")
        #expect(mode.activePluginID == "devtools")

        mode.navigate(to: "clipboard", name: "剪贴板", icon: "doc.on.clipboard", context: ["filter": "text"])
        #expect(mode.activePluginID == "clipboard")
        #expect(mode.activePluginName == "剪贴板")
        #expect(mode.context["filter"] == "text")
    }

    @Test("协调器 navigate 同步到 PaletteMode")
    func coordinatorNavigateSyncsPaletteMode() {
        let coordinator = PaletteCoordinator()
        let mode = coordinator.paletteMode

        #expect(mode.isPluginMode == false)

        coordinator.navigate(to: "devtools", context: ["tool": "json"])

        #expect(mode.isPluginMode == true)
        #expect(mode.activePluginID == "devtools")
        #expect(mode.context["tool"] == "json")

        coordinator.hide(restoreFocus: false)
    }

    @Test("协调器 popToRoot 同步到 PaletteMode")
    func coordinatorPopToRootSyncsPaletteMode() {
        let coordinator = PaletteCoordinator()
        let mode = coordinator.paletteMode

        coordinator.navigate(to: "clipboard")
        #expect(mode.isPluginMode == true)

        coordinator.popToRoot()
        #expect(mode.isPluginMode == false)
        #expect(mode.activePluginID == nil)

        coordinator.hide(restoreFocus: false)
    }
}
