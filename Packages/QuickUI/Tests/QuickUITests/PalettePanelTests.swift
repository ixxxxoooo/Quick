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
