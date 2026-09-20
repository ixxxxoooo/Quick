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
        #expect(mode.activeModuleID == nil)
        #expect(mode.isModuleMode == false)
        #expect(mode.context.isEmpty)
        #expect(mode.activeModuleName == nil)
        #expect(mode.activeModuleIcon == nil)
    }

    @Test("navigate 切换到模块模式")
    func navigateToModule() {
        let mode = PaletteMode()
        mode.navigate(to: "devtools", name: "开发工具", icon: "wrench.and.screwdriver", context: ["tool": "json"])

        #expect(mode.activeModuleID == "devtools")
        #expect(mode.isModuleMode == true)
        #expect(mode.activeModuleName == "开发工具")
        #expect(mode.activeModuleIcon == "wrench.and.screwdriver")
        #expect(mode.context["tool"] == "json")
    }

    @Test("popToRoot 返回搜索模式")
    func popToRootClearsState() {
        let mode = PaletteMode()
        mode.navigate(to: "clipboard", name: "剪贴板", icon: "doc.on.clipboard")

        #expect(mode.isModuleMode == true)

        mode.popToRoot()

        #expect(mode.activeModuleID == nil)
        #expect(mode.isModuleMode == false)
        #expect(mode.activeModuleName == nil)
        #expect(mode.activeModuleIcon == nil)
        #expect(mode.context.isEmpty)
    }

    @Test("多次 navigate 切换模块")
    func switchBetweenModules() {
        let mode = PaletteMode()

        mode.navigate(to: "devtools", name: "开发工具", icon: "wrench.and.screwdriver")
        #expect(mode.activeModuleID == "devtools")

        mode.navigate(to: "clipboard", name: "剪贴板", icon: "doc.on.clipboard", context: ["filter": "text"])
        #expect(mode.activeModuleID == "clipboard")
        #expect(mode.activeModuleName == "剪贴板")
        #expect(mode.context["filter"] == "text")
    }

    @Test("协调器 navigate 同步到 PaletteMode")
    func coordinatorNavigateSyncsPaletteMode() {
        let coordinator = PaletteCoordinator()
        let mode = coordinator.paletteMode

        #expect(mode.isModuleMode == false)

        coordinator.navigate(to: "devtools", context: ["tool": "json"])

        #expect(mode.isModuleMode == true)
        #expect(mode.activeModuleID == "devtools")
        #expect(mode.context["tool"] == "json")

        coordinator.hide(restoreFocus: false)
    }

    @Test("协调器 popToRoot 同步到 PaletteMode")
    func coordinatorPopToRootSyncsPaletteMode() {
        let coordinator = PaletteCoordinator()
        let mode = coordinator.paletteMode

        coordinator.navigate(to: "clipboard")
        #expect(mode.isModuleMode == true)

        coordinator.popToRoot()
        #expect(mode.isModuleMode == false)
        #expect(mode.activeModuleID == nil)

        coordinator.hide(restoreFocus: false)
    }
}
