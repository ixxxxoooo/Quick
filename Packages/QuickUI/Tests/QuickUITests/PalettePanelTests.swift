// PalettePanelTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import QuickUI

@MainActor
@Suite("PalettePanel 浮窗行为")
struct PalettePanelTests {

    /// 菜单栏唤起后应用会失活，面板绝不能因此自动隐藏
    @Test("hidesOnDeactivate 必须为 false")
    func doesNotHideOnDeactivate() {
        let panel = PalettePanel(rootView: Text("Quick"))
        #expect(panel.hidesOnDeactivate == false)
        #expect(panel.canBecomeKey)
        #expect(panel.isFloatingPanel)
        panel.close()
    }

    /// 设计令牌尺寸应保证面板可见
    @Test("面板尺寸有效")
    func panelSizeIsValid() {
        #expect(DesignTokens.Size.panelWidth > 0)
        #expect(DesignTokens.Size.panelHeight > 0)
    }

    /// 面板几何与设计基准一致
    ///
    /// 这几个数字是**从基准截图反推出来的**：截图 1650×1046 物理像素，macOS 截图是 2x，
    /// 所以逻辑尺寸 825×523；两个维度都精确等于基础令牌 ×1.1，对应参考实现的
    /// 「Large」档。推导过程见 `DesignTokens.panelScale` 的文档注释。
    ///
    /// 正因为它是推出来的、不是拍出来的，必须有测试守着 —— 否则下次有人改尺寸，
    /// 就再也没人说得清基准到底是什么了。
    @Test("面板几何与设计基准一致")
    func panelGeometryMatchesDesignReference() {
        #expect(DesignTokens.panelScale == 1.1)
        #expect(DesignTokens.Size.panelWidth == 825)
        #expect(DesignTokens.Size.panelHeight == 523)
        #expect(DesignTokens.Radius.panel == 29)
    }

    /// 细线不随面板缩放
    ///
    /// 它是物理像素级的东西：跟着放大只会变成一条粗边。
    @Test("细线不随面板缩放")
    func hairlineDoesNotScale() {
        #expect(DesignTokens.Size.hairline == 1)
        #expect(DesignTokens.panelScale != 1)
    }

    // MARK: - 缩放（与分离窗口同一套）

    /// 主面板与分离窗口共用同一套系统缩放：靠 `.resizable` 拿系统热区，不再自绘透明边框。
    @Test("主面板用 .resizable 缩放并带最小尺寸")
    func panelUsesNativeResize() {
        let panel = PalettePanel(rootView: Text("t"))
        #expect(panel.styleMask.contains(.resizable))
        #expect(panel.minSize.width >= DesignTokens.Size.panelMinWidth)
        #expect(panel.minSize.height >= DesignTokens.Size.panelMinHeight)
        panel.close()
    }

    /// 缩放上限按窗口所在屏幕夹，下限是设计令牌的 0.6 倍
    @Test("窗口缩放在 delegate 里夹到屏幕与最小值之间")
    func windowWillResizeClampsToScreen() {
        let panel = PalettePanel(rootView: Text("t"))

        let huge = panel.windowWillResize(panel, to: NSSize(width: 99999, height: 99999))
        if let screen = panel.screen ?? NSScreen.main {
            #expect(huge.width <= screen.visibleFrame.width)
            #expect(huge.height <= screen.visibleFrame.height)
        }
        #expect(huge.width >= DesignTokens.Size.panelMinWidth)
        #expect(huge.height >= DesignTokens.Size.panelMinHeight)

        let tiny = panel.windowWillResize(panel, to: NSSize(width: 1, height: 1))
        #expect(tiny.width == DesignTokens.Size.panelMinWidth)
        #expect(tiny.height == DesignTokens.Size.panelMinHeight)

        panel.close()
    }

    /// 协调器显隐状态在 show/hide 后应一致
    @Test("协调器 show/hide 状态")
    func coordinatorShowHide() {
        let coordinator = PaletteCoordinator()
        #expect(coordinator.isVisible == false)
        coordinator.show()
        #expect(coordinator.isVisible == true)
        coordinator.hide(restoreFocus: false)
        #expect(coordinator.isVisible == false)
    }

    /// 面板在失活时仍应保持可见配置
    @Test("浮窗不会因失活自动隐藏")
    func panelSurvivesDeactivateConfig() {
        let panel = PalettePanel(rootView: Text("t"))
        #expect(panel.hidesOnDeactivate == false)
        panel.orderFrontRegardless()
        #expect(panel.isVisible)
        panel.orderOut(nil)
    }

    // MARK: - Esc

    /// Esc 的三层优先级
    @Test("Esc 动作决策：插件 → 有输入 → 关闭")
    func escapeActionDecision() {
        #expect(PaletteCoordinator.escapeAction(isPluginMode: true, query: "") == .popToRoot)
        // 插件模式下搜索框里的残留内容不算数：屏幕上根本没有搜索框
        #expect(PaletteCoordinator.escapeAction(isPluginMode: true, query: "abc") == .popToRoot)
        #expect(PaletteCoordinator.escapeAction(isPluginMode: false, query: "abc") == .clearQuery)
        #expect(PaletteCoordinator.escapeAction(isPluginMode: false, query: "") == .dismiss)
    }

    /// 搜索框有内容时 Esc 清空而不关面板，清空后再按才关闭
    @Test("Esc 先清空搜索框，再按才关闭面板")
    func escapeClearsQueryBeforeDismissing() {
        let coordinator = PaletteCoordinator()
        coordinator.show()
        coordinator.query = "计算器"

        coordinator.handleEscape()
        #expect(coordinator.query == "")
        #expect(coordinator.isVisible)

        coordinator.handleEscape()
        #expect(coordinator.isVisible == false)
        coordinator.hide(restoreFocus: false)
    }

    /// 插件模式下 Esc 仍然只是退回搜索，不关面板
    @Test("插件模式下 Esc 退回搜索而不关面板")
    func escapeInPluginModePopsToRoot() {
        let coordinator = PaletteCoordinator()
        coordinator.navigate(to: "demo")
        #expect(coordinator.activePluginID == "demo")

        coordinator.handleEscape()
        #expect(coordinator.activePluginID == nil)
        #expect(coordinator.isVisible)
        coordinator.hide(restoreFocus: false)
    }

    /// 按键路由：Esc 走 `onEscape`，⌘W 走 `onClose`    ///
    /// 这两条路必须分开 —— 合并的话 ⌘W 会退化成「清空搜索框」，
    /// 而用户按 ⌘W 想的是关掉面板。
    @Test("Esc 与 ⌘W 走各自回调")
    func escapeAndCommandWRouting() {
        let panel = PalettePanel(rootView: Text("t"))
        var escaped = 0
        var closed = 0
        panel.onEscape = {
            escaped += 1
            return true
        }
        panel.onClose = { closed += 1 }

        guard let escape = Self.keyDown(keyCode: kVK_Escape, modifiers: [], characters: "\u{1B}"),
            let commandW = Self.keyDown(keyCode: kVK_ANSI_W, modifiers: .command, characters: "w")
        else {
            Issue.record("无法构造合成按键事件")
            return
        }

        panel.sendEvent(escape)
        #expect(escaped == 1)
        #expect(closed == 0)

        panel.sendEvent(commandW)
        #expect(escaped == 1)
        #expect(closed == 1)

        panel.close()
    }

    /// 插件内搜索的按键路由：`wantsNavigation` 为真才消费，否则放行给插件视图
    @Test("插件模式上下/左右/回车按 wantsNavigation 决定是否消费")
    func pluginSearchKeyRouting() {
        let coordinator = PaletteCoordinator()
        coordinator.navigate(to: "clipboard")

        // 插件没有声明要吃按键时，三个键都必须放行
        #expect(coordinator.routeMove(1) == false)
        #expect(coordinator.routeTab(-1) == false)
        #expect(coordinator.routeSubmit() == false)
        #expect(coordinator.pluginSearch.lastCommand == nil)

        coordinator.pluginSearch.wantsNavigation = true
        #expect(coordinator.routeMove(1))
        #expect(coordinator.pluginSearch.lastCommand == .move(1))
        #expect(coordinator.routeTab(-1))
        #expect(coordinator.pluginSearch.lastCommand == .tab(-1))
        #expect(coordinator.routeSubmit())
        #expect(coordinator.pluginSearch.lastCommand == .submit)

        coordinator.hide(restoreFocus: false)
    }

    /// 同插件二次 show：视图还在树上时 onAppear 不会再跑，必须靠 shownToken 唤醒导航
    @Test("插件二次 show 会递增 shownToken")
    func reShowPluginNotifiesShownToken() {
        let coordinator = PaletteCoordinator()
        coordinator.show(pluginID: "clipboard")
        let afterFirst = coordinator.pluginSearch.shownToken
        #expect(afterFirst >= 1)

        coordinator.hide(restoreFocus: false)
        coordinator.show(pluginID: "clipboard")
        #expect(coordinator.pluginSearch.shownToken == afterFirst + 1)

        coordinator.hide(restoreFocus: false)
    }

    /// 主搜索模式下左右键属于搜索框光标，必须放行
    @Test("主搜索模式下左右键不被面板消费")
    func mainSearchDoesNotConsumeTab() {
        let coordinator = PaletteCoordinator()
        #expect(coordinator.routeTab(1) == false)
        #expect(coordinator.routeMove(1) == false)
    }

    /// ⌘F 只在「插件模式 + 该插件有头部搜索框」时被消费，并且会请求一次聚焦
    @Test("⌘F 请求插件搜索框聚焦")
    func commandFRequestsPluginSearchFocus() {
        let coordinator = PaletteCoordinator()
        #expect(coordinator.requestPluginSearchFocus() == false)

        coordinator.navigate(to: "clipboard")
        let before = coordinator.pluginSearch.focusToken
        #expect(coordinator.requestPluginSearchFocus())
        #expect(coordinator.pluginSearch.focusToken == before + 1)

        coordinator.hide(restoreFocus: false)
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

@Suite("面板高度与授权面板吸附")
struct PaletteGeometryTests {

    @Test("拖出来的高度不会矮过下限，也不会高出屏幕")
    func clampsPanelHeight() {
        let floor = DesignTokens.Size.panelMinHeight
        #expect(PalettePreferences.clampedPanelHeight(1, maxHeight: 2000) == floor)
        #expect(PalettePreferences.clampedPanelHeight(9000, maxHeight: 800) == 800)
        #expect(PalettePreferences.clampedPanelHeight(600, maxHeight: 2000) == 600)
    }

    @Test("拖出来的宽度不会窄过下限，也不会宽出屏幕")
    func clampsPanelWidth() {
        let floor = DesignTokens.Size.panelMinWidth
        #expect(PalettePreferences.clampedPanelWidth(1, maxWidth: 3000) == floor)
        #expect(PalettePreferences.clampedPanelWidth(9000, maxWidth: 1200) == 1200)
        #expect(PalettePreferences.clampedPanelWidth(900, maxWidth: 3000) == 900)
    }

    @Test("授权面板宽度跟随系统设置右侧内容区")
    func permissionPanelWidthMatchesContentArea() {
        let settings = CGRect(x: 100, y: 400, width: 900, height: 700)
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let width = PermissionSnapGeometry.width(settings: settings, screen: screen)
        #expect(width == settings.width - DesignTokens.Size.systemSettingsSidebar)
    }

    @Test("内容区比屏幕还宽时按屏幕收窄")
    func permissionPanelWidthClampsToScreen() {
        let settings = CGRect(x: 0, y: 400, width: 5000, height: 700)
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let width = PermissionSnapGeometry.width(settings: settings, screen: screen)
        #expect(width == screen.width - DesignTokens.Spacing.lg * 2)
    }

    @Test("授权面板贴在系统设置右侧内容区的正下方")
    func snapsUnderSystemSettings() {
        let settings = CGRect(x: 100, y: 400, width: 900, height: 700)
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let width = PermissionSnapGeometry.width(settings: settings, screen: screen)
        let frame = PermissionSnapGeometry.frame(
            settings: settings, screen: screen, panelWidth: width, panelHeight: 160)
        #expect(frame.minX == settings.minX + DesignTokens.Size.systemSettingsSidebar)
        #expect(frame.maxY == settings.minY)
        #expect(frame.width == width)
        #expect(frame.height == 160)
    }
}
