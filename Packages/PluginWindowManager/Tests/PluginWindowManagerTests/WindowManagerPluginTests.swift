// WindowManagerPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginWindowManager

/// 浮点比例乘出来的矩形不能拿 `==` 比（0.15 × 1000 在二进制浮点里不是恰好 150），
/// 所以统一按容差比较，而不是把期望值写成算出来的同一个表达式
private let tolerance: CGFloat = 1e-9

@Suite("窗口布局几何")
struct WindowGeometryTests {

    // 一块 1000 × 800、原点在原点的可见区域，期望值全部是手算的
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func frame(_ layout: WindowLayout) -> CGRect {
        WindowGeometry.frame(in: screen, layout: layout)
    }

    @Test("左半屏：x 不变，宽取一半，高满屏")
    func leftHalf() {
        let f = frame(.leftHalf)

        #expect(abs(f.minX - 0) < tolerance)
        #expect(abs(f.minY - 0) < tolerance)
        #expect(abs(f.width - 500) < tolerance)
        #expect(abs(f.height - 800) < tolerance)
    }

    @Test("右半屏：x 偏出半个屏宽")
    func rightHalf() {
        let f = frame(.rightHalf)

        #expect(abs(f.minX - 500) < tolerance)
        #expect(abs(f.minY - 0) < tolerance)
        #expect(abs(f.width - 500) < tolerance)
        #expect(abs(f.height - 800) < tolerance)
    }

    @Test("上半屏落在可见区域顶部（AppKit 里是 y 更大的一侧）")
    func topHalf() {
        let f = frame(.topHalf)

        #expect(abs(f.minX - 0) < tolerance)
        #expect(abs(f.minY - 400) < tolerance)
        #expect(abs(f.width - 1000) < tolerance)
        #expect(abs(f.height - 400) < tolerance)
        // 比例里的 y=0 是「屏幕顶部」，翻到 AppKit 坐标后应当贴着可见区域上沿
        #expect(abs(f.maxY - screen.maxY) < tolerance)
    }

    @Test("下半屏落在可见区域底部")
    func bottomHalf() {
        let f = frame(.bottomHalf)

        #expect(abs(f.minX - 0) < tolerance)
        #expect(abs(f.minY - 0) < tolerance)
        #expect(abs(f.width - 1000) < tolerance)
        #expect(abs(f.height - 400) < tolerance)
    }

    @Test("最大化等于整个可见区域")
    func maximize() {
        let f = frame(.maximize)

        #expect(abs(f.minX - screen.minX) < tolerance)
        #expect(abs(f.minY - screen.minY) < tolerance)
        #expect(abs(f.width - screen.width) < tolerance)
        #expect(abs(f.height - screen.height) < tolerance)
    }

    @Test("居中：0.15/0.1 的留白与 0.7/0.8 的尺寸")
    func center() {
        let f = frame(.center)

        #expect(abs(f.minX - 150) < tolerance)
        #expect(abs(f.minY - 80) < tolerance)
        #expect(abs(f.width - 700) < tolerance)
        #expect(abs(f.height - 640) < tolerance)
    }

    @Test("四个角各占四分之一屏")
    func quarters() {
        let topLeft = frame(.topLeft)
        let topRight = frame(.topRight)
        let bottomLeft = frame(.bottomLeft)
        let bottomRight = frame(.bottomRight)

        #expect(abs(topLeft.minX - 0) < tolerance && abs(topLeft.minY - 400) < tolerance)
        #expect(abs(topRight.minX - 500) < tolerance && abs(topRight.minY - 400) < tolerance)
        #expect(abs(bottomLeft.minX - 0) < tolerance && abs(bottomLeft.minY - 0) < tolerance)
        #expect(abs(bottomRight.minX - 500) < tolerance && abs(bottomRight.minY - 0) < tolerance)

        for quarter in [topLeft, topRight, bottomLeft, bottomRight] {
            #expect(abs(quarter.width - 500) < tolerance)
            #expect(abs(quarter.height - 400) < tolerance)
        }
    }

    @Test("可见区域有偏移时矩形跟着平移")
    func offsetVisibleFrame() {
        // 菜单栏 + Dock 让可见区域不贴屏幕原点时，结果必须整体平移而不是重新从 0 算起
        let offset = CGRect(x: 100, y: 50, width: 1000, height: 800)

        let left = WindowGeometry.frame(in: offset, layout: .leftHalf)
        #expect(abs(left.minX - 100) < tolerance)
        #expect(abs(left.minY - 50) < tolerance)
        #expect(abs(left.width - 500) < tolerance)
        #expect(abs(left.height - 800) < tolerance)

        let centered = WindowGeometry.frame(in: offset, layout: .center)
        #expect(abs(centered.minX - 250) < tolerance)
        #expect(abs(centered.minY - 130) < tolerance)
        #expect(abs(centered.width - 700) < tolerance)
        #expect(abs(centered.height - 640) < tolerance)
    }

    @Test("AX 位置用左上原点：上半屏 y 为 0，下半屏 y 为半屏高")
    func accessibilityPositionUsesTopLeftOrigin() {
        let top = WindowGeometry.accessibilityPosition(in: screen, layout: .topHalf)
        let bottom = WindowGeometry.accessibilityPosition(in: screen, layout: .bottomHalf)

        #expect(abs(top.x - 0) < tolerance)
        #expect(abs(top.y - 0) < tolerance)
        #expect(abs(bottom.x - 0) < tolerance)
        #expect(abs(bottom.y - 400) < tolerance)
    }

    @Test("AX 位置以可见区域的上沿为翻转基准")
    func accessibilityPositionIsRelativeToVisibleFrame() {
        let offset = CGRect(x: 100, y: 50, width: 1000, height: 800)

        let left = WindowGeometry.accessibilityPosition(in: offset, layout: .leftHalf)
        let centered = WindowGeometry.accessibilityPosition(in: offset, layout: .center)

        #expect(abs(left.x - 100) < tolerance)
        #expect(abs(left.y - 0) < tolerance)
        #expect(abs(centered.x - 250) < tolerance)
        #expect(abs(centered.y - 80) < tolerance)
    }

    @Test("AX 尺寸与 frame 的尺寸一致")
    func accessibilitySizeMatchesFrame() {
        for layout in WindowLayout.allCases {
            let f = WindowGeometry.frame(in: screen, layout: layout)
            let s = WindowGeometry.accessibilitySize(in: screen, layout: layout)

            #expect(abs(s.width - f.width) < tolerance, "布局 \(layout.rawValue) 宽度不一致")
            #expect(abs(s.height - f.height) < tolerance, "布局 \(layout.rawValue) 高度不一致")
        }
    }

    @Test("每种布局都落在可见区域内且面积为正")
    func everyLayoutStaysInsideVisibleFrame() {
        for layout in WindowLayout.allCases {
            let f = WindowGeometry.frame(in: screen, layout: layout)

            #expect(f.width > 0, "布局 \(layout.rawValue) 宽度非正")
            #expect(f.height > 0, "布局 \(layout.rawValue) 高度非正")
            #expect(f.minX >= screen.minX - tolerance, "布局 \(layout.rawValue) 越出左边界")
            #expect(f.minY >= screen.minY - tolerance, "布局 \(layout.rawValue) 越出下边界")
            #expect(f.maxX <= screen.maxX + tolerance, "布局 \(layout.rawValue) 越出右边界")
            #expect(f.maxY <= screen.maxY + tolerance, "布局 \(layout.rawValue) 越出上边界")
        }
    }

    @Test("左右半屏正好拼满可见区域")
    func halvesTileTheScreen() {
        let left = WindowGeometry.frame(in: screen, layout: .leftHalf)
        let right = WindowGeometry.frame(in: screen, layout: .rightHalf)

        #expect(abs(left.maxX - right.minX) < tolerance)
        #expect(abs(left.width + right.width - screen.width) < tolerance)
    }
}

@Suite("窗口管理插件契约")
@MainActor
struct WindowManagerPluginTests {

    @Test("插件 id 是 kebab-case 且等于约定值")
    func identifierIsKebabCase() {
        let id = WindowManagerPlugin.id

        #expect(id == "windowmanager")
        #expect(id == id.lowercased())
        #expect(id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        #expect(!id.hasPrefix("-") && !id.hasSuffix("-") && !id.contains("--"))
    }

    @Test("名称、图标、触发词齐备")
    func metadataIsComplete() {
        #expect(WindowManagerPlugin.name == "窗口管理")
        #expect(WindowManagerPlugin.icon == "macwindow")
        #expect(
            WindowManagerPlugin.triggerWords == ["窗口", "window", "平铺", "布局", "半屏", "全屏"]
        )
        #expect(WindowManagerPlugin.triggerWords.allSatisfy { !$0.isEmpty })
    }

    @Test("只打触发词时列出全部布局")
    func triggerWordListsAllLayouts() async {
        let plugin = WindowManagerPlugin()
        let results = await plugin.searchItems(query: "窗口")

        // 触发词被剥离后查询词为空，应当按「没有条件」处理，列出全部 10 种布局
        #expect(results.count == WindowLayout.allCases.count)
        #expect(results.allSatisfy { $0.pluginID == WindowManagerPlugin.id })
        #expect(results.allSatisfy { $0.relevance == 0.5 })
        #expect(
            Set(results.map(\.id))
                == Set(WindowLayout.allCases.map { "windowmanager.\($0.rawValue)" }))
    }

    @Test("触发词加关键词只留下匹配的布局")
    func keywordNarrowsLayouts() async throws {
        let plugin = WindowManagerPlugin()
        let results = await plugin.searchItems(query: "窗口 左")

        // 「左」前缀命中 leftHalf / topLeft / bottomLeft 三个布局的关键词
        #expect(results.count == 3)
        #expect(
            Set(results.map(\.id)) == [
                "windowmanager.left", "windowmanager.topLeft", "windowmanager.bottomLeft"
            ])
        #expect(results.allSatisfy { $0.pluginID == WindowManagerPlugin.id })
        // 命中前缀的 fuzzyScore 是 0.9，再乘 0.7
        #expect(results.allSatisfy { abs($0.relevance - 0.63) < 1e-9 })
    }

    @Test("无关查询与空查询不返回结果")
    func unrelatedQueryYieldsNothing() async {
        let plugin = WindowManagerPlugin()

        #expect(await plugin.searchItems(query: "").isEmpty)
        #expect(await plugin.searchItems(query: "天气").isEmpty)
        #expect(await plugin.searchItems(query: "system preferences").isEmpty)
    }
}
