// PalettePanelTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
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
}
