// SuperPanelPlacementTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics
import Testing
@testable import QuickUI

@Suite("超级面板落点")
struct SuperPanelPlacementTests {

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 390, height: 320)

    @Test("默认在光标右下方展开")
    func defaultDownRight() {
        let placement = SuperPanelPlacement.resolve(
            cursor: CGPoint(x: 700, y: 500), panelSize: size, visibleFrame: screen)
        #expect(placement.horizontal == .right)
        #expect(placement.vertical == .down)
        let origin = placement.origin(for: size, visibleFrame: screen)
        #expect(abs(origin.x - 706) < 0.01)
        #expect(abs(origin.y - 174) < 0.01)
    }

    @Test("右侧空间不足翻到左侧")
    func flipsLeft() {
        let placement = SuperPanelPlacement.resolve(
            cursor: CGPoint(x: 1300, y: 500), panelSize: size, visibleFrame: screen)
        #expect(placement.horizontal == .left)
        let origin = placement.origin(for: size, visibleFrame: screen)
        #expect(abs(origin.x - 904) < 0.01)
    }

    @Test("下方空间不足翻到上方")
    func flipsUp() {
        let placement = SuperPanelPlacement.resolve(
            cursor: CGPoint(x: 700, y: 200), panelSize: size, visibleFrame: screen)
        #expect(placement.vertical == .up)
        let origin = placement.origin(for: size, visibleFrame: screen)
        #expect(abs(origin.y - 206) < 0.01)
    }

    @Test("角落被夹进屏幕可见区")
    func clampsIntoVisibleFrame() {
        let placement = SuperPanelPlacement.resolve(
            cursor: CGPoint(x: 0, y: 0), panelSize: size, visibleFrame: screen)
        let origin = placement.origin(for: size, visibleFrame: screen)
        #expect(origin.x >= SuperPanelPlacement.margin - 0.01)
        #expect(origin.y >= SuperPanelPlacement.margin - 0.01)
    }

    @Test("高度变化以光标为锚点重定位")
    func heightChangeKeepsAnchor() {
        let placement = SuperPanelPlacement.resolve(
            cursor: CGPoint(x: 700, y: 500), panelSize: size, visibleFrame: screen)
        let taller = CGSize(width: 390, height: 400)
        let origin = placement.origin(for: taller, visibleFrame: screen)
        // 向下的面板顶边固定在光标下方 6pt，长高时只向下撑开
        #expect(abs((origin.y + taller.height) - (500 - SuperPanelPlacement.offset)) < 0.01)
    }
}
