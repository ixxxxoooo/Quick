// ToolbarPlacementTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics
import Testing

@testable import PluginScreenshot

@Suite("标注工具栏摆放")
struct ToolbarPlacementTests {

    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)
    private let size = CGSize(width: 400, height: 40)
    private let margin: CGFloat = 10

    private func place(_ selection: CGRect) -> CGRect {
        ToolbarPlacement.frame(near: selection, size: size, in: bounds, margin: margin)
    }

    @Test("选区下方放得下：贴在下方，与选区左缘对齐")
    func belowWhenFits() {
        let frame = place(CGRect(x: 100, y: 200, width: 300, height: 200))
        #expect(frame.minX == 100)
        #expect(frame.maxY == 200 - margin)
    }

    @Test("下方放不下：翻到上方")
    func aboveWhenBelowOverflows() {
        let selection = CGRect(x: 100, y: 20, width: 300, height: 200)
        let frame = place(selection)
        #expect(frame.minY == selection.maxY + margin)
    }

    @Test("上下都放不下：落在选区内部底边，且不出画布")
    func insideWhenNoRoom() {
        let frame = place(bounds)
        #expect(frame.minY == bounds.minY + margin)
        #expect(bounds.contains(frame))
    }

    @Test("靠右的选区：水平方向夹在画布内")
    func clampsHorizontally() {
        let frame = place(CGRect(x: 900, y: 300, width: 90, height: 100))
        #expect(frame.maxX == bounds.maxX - margin)
        let left = place(CGRect(x: -50, y: 300, width: 90, height: 100))
        #expect(left.minX == margin)
    }

    @Test("工具栏比画布还宽：贴左，不出现负坐标")
    func widerThanCanvas() {
        let frame = ToolbarPlacement.frame(
            near: CGRect(x: 10, y: 300, width: 50, height: 50),
            size: CGSize(width: 1200, height: 40), in: bounds, margin: margin)
        #expect(frame.minX == margin)
    }

    @Test("任何选区下结果都落在画布内")
    func alwaysInsideBounds() {
        for x in stride(from: -50.0, through: 1000.0, by: 125.0) {
            for y in stride(from: -50.0, through: 700.0, by: 117.0) {
                let frame = place(CGRect(x: x, y: y, width: 120, height: 90))
                #expect(frame.minY >= bounds.minY)
                #expect(frame.maxY <= bounds.maxY)
                #expect(frame.minX >= bounds.minX)
                #expect(frame.maxX <= bounds.maxX)
            }
        }
    }
}

@Suite("标注默认值")
struct AnnotationDefaultsTests {

    @Test("默认线宽必须是三档之一，工具栏高亮才与实际画出来的一致")
    func defaultWidthIsOneOfTheChoices() {
        #expect(AnnotationDefaults.lineWidths.contains(AnnotationDefaults.lineWidth))
    }

    @Test("线宽档位严格递增")
    func widthsAscending() {
        let widths = AnnotationDefaults.lineWidths
        #expect(widths == widths.sorted())
        #expect(Set(widths).count == widths.count)
    }

    @Test("默认颜色在调色板里")
    func defaultColorInPalette() {
        #expect(RGBAColor.palette.contains(AnnotationDefaults.color))
    }
}
