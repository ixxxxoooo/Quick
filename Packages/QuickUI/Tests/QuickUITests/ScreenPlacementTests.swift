// ScreenPlacementTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Testing
@testable import QuickUI

@Suite("按指针挑屏幕")
struct ScreenPlacementTests {

    /// 左右并排：两块屏各自的内部都命中自己
    @Test("并排的两块屏各归各位")
    func sideBySide() {
        let left = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let right = CGRect(x: 2560, y: 0, width: 1512, height: 982)
        let frames = [left, right]

        #expect(ScreenPlacement.screenIndex(containing: CGPoint(x: 100, y: 100), frames: frames) == 0)
        #expect(ScreenPlacement.screenIndex(containing: CGPoint(x: 3000, y: 500), frames: frames) == 1)
    }

    /// 上下错位排列：第二块屏只占右半边时，左半边下方是**空隙**
    ///
    /// 这是真实会出现的摆法（笔记本 + 显示器），指针落在空隙里时不能瞎猜一块屏。
    @Test("屏幕之间的空隙不命中任何一块")
    func gapBetweenStaggeredScreens() {
        let top = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let belowRight = CGRect(x: 1400, y: 1440, width: 1512, height: 982)
        let frames = [top, belowRight]

        // 右下那块屏的内部
        #expect(
            ScreenPlacement.screenIndex(containing: CGPoint(x: 2000, y: 2000), frames: frames) == 1)
        // 左半边下方：没有屏幕
        #expect(ScreenPlacement.screenIndex(containing: CGPoint(x: 300, y: 2000), frames: frames) == nil)
    }

    /// 贴合边只属于其中一块，不会两块都算命中
    @Test("贴合边只命中一块")
    func sharedEdgeBelongsToOneScreen() {
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let frames = [left, right]

        let index = ScreenPlacement.screenIndex(containing: CGPoint(x: 1000, y: 400), frames: frames)
        #expect(index == 1)
    }

    /// 没有屏幕时返回 nil，由调用方决定退路
    @Test("没有屏幕时返回 nil")
    func noScreens() {
        #expect(ScreenPlacement.screenIndex(containing: .zero, frames: []) == nil)
    }
}

@MainActor
@Suite("分离窗口落点")
struct DetachedOriginTests {

    /// 一块 1512×982 的屏，可用区域去掉菜单栏与 Dock
    private let visible = NSRect(x: 0, y: 0, width: 1512, height: 940)
    private let size = CGSize(width: 809, height: 513)

    /// 没有源窗口时在**这块屏**上居中 —— 不是主屏居中
    @Test("没有源窗口时在目标屏居中")
    func centersOnTargetScreen() {
        let origin = PluginPanelController.detachedOrigin(
            size: size, sourceFrame: nil, visibleFrame: visible)

        #expect(origin.x == visible.midX - size.width / 2)
        #expect(origin.y == visible.midY - size.height / 2)
        // 完全落在这块屏里
        #expect(origin.x >= visible.minX)
        #expect(origin.y >= visible.minY)
        #expect(origin.x + size.width <= visible.maxX)
        #expect(origin.y + size.height <= visible.maxY)
    }

    /// 有源窗口时贴着它偏移
    ///
    /// 源窗口放在中间：贴着上边或右边时会被夹取（那是另一条测试），
    /// 这条只验「偏移量本身」。
    @Test("有源窗口时贴着它偏移")
    func offsetsFromSourceWindow() {
        let source = NSRect(x: 300, y: 300, width: 809, height: 513)
        let origin = PluginPanelController.detachedOrigin(
            size: size, sourceFrame: source, visibleFrame: visible)

        #expect(origin.x == source.origin.x + 30)
        #expect(origin.y == source.origin.y - 30)
    }

    /// 源窗口贴着右下角时，偏移不能把窗口推出屏外
    @Test("源窗口贴边时夹回屏内")
    func clampsWhenSourceIsAtEdge() {
        let source = NSRect(x: visible.maxX - 100, y: visible.minY, width: 809, height: 513)
        let origin = PluginPanelController.detachedOrigin(
            size: size, sourceFrame: source, visibleFrame: visible)

        #expect(origin.x + size.width <= visible.maxX)
        #expect(origin.y >= visible.minY)
    }

    /// 窗口比屏幕还大时贴住最小边，而不是跑到屏外
    @Test("窗口比屏幕大时贴住最小边")
    func oversizedWindowPinsToOrigin() {
        let huge = CGSize(width: 4000, height: 3000)
        let origin = PluginPanelController.detachedOrigin(
            size: huge, sourceFrame: nil, visibleFrame: visible)

        #expect(origin.x == visible.minX)
        #expect(origin.y == visible.minY)
    }
}
