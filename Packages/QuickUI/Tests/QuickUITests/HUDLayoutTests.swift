// HUDLayoutTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI
import Testing

@testable import QuickUI

/// HUD 的尺寸
///
/// 汇报形式是「拍一张画面看文字有没有被截」：`fittingSize` 本身是正常的（宽度会随文案增长），
/// 出问题的是它的小数部分 —— 窗口 frame 落到整数上，少的半个点就让文字排不下，
/// 而 SwiftUI 的截断是整段的，于是「已复制」直接变成「已…」。所以断言必须落在**渲染结果**上，
/// 只比尺寸是测不出这个回归的。
@Suite("HUD 尺寸")
@MainActor
struct HUDLayoutTests {

    /// 起一个真实的 HUD 窗口，返回它（`HUDController` 不暴露窗口）
    private func showHUD(_ message: String) throws -> NSWindow {
        let app = NSApplication.shared
        let existing = Set(app.windows.map(ObjectIdentifier.init))

        let hud = HUDController()
        hud.show(message: message)

        let created = app.windows.filter { !existing.contains(ObjectIdentifier($0)) }
        return try #require(created.last, "HUD 没有建出窗口")
    }

    /// 文字画出来的宽度（点）
    ///
    /// 只量黑色像素：图标是绿的、胶囊是浅色的，黑色只可能来自文案。
    /// 截断与否在这个量上有量级差别 —— 「已复制」完整是 36.5pt，被截成「已…」只剩 23pt。
    private func textInkWidth(in view: NSView) -> Double {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: rep)

        var minX = rep.pixelsWide
        var maxX = -1
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                // 透明区域的 RGB 也是 0，必须连 alpha 一起判
                guard color.alphaComponent > 0.5 else { continue }
                guard color.redComponent < 0.35, color.greenComponent < 0.35,
                    color.blueComponent < 0.35
                else { continue }
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        return maxX >= minX ? Double(maxX - minX + 1) / 2 : 0
    }

    /// 回归测试：窗口按内容自身宽度打开时，文案必须是完整的
    @Test("短文案不会被截断")
    func shortMessageIsNotTruncated() throws {
        let window = try showHUD("已复制")
        let content = try #require(window.contentView)

        // 自然宽度下画出来的文字
        let natural = textInkWidth(in: content)

        // 给足额外宽度再画一次：如果自然宽度下排不下，两次的墨迹宽度会差一截
        window.setFrame(
            NSRect(
                x: window.frame.origin.x, y: window.frame.origin.y,
                width: window.frame.width + 60, height: window.frame.height),
            display: true)
        content.layoutSubtreeIfNeeded()
        let roomy = textInkWidth(in: content)

        #expect(natural >= roomy - 0.5, "自然宽度 \(natural)pt，给足宽度 \(roomy)pt —— 被截断了")
    }

    /// 上限仍然生效：`hudMaxWidth` 是**整个胶囊**的最大宽度，文案再长也不越过它
    @Test("超长文案被上限兜住")
    func veryLongMessageRespectsCap() throws {
        let window = try showHUD(String(repeating: "很长的提示文案", count: 12))

        // 只留一点取整余量
        #expect(window.frame.width <= DesignTokens.Size.hudMaxWidth + 2)
    }

    /// 文案再长也不折行：HUD 是单行提示，折行会把胶囊撑成方块
    @Test("超长文案不折行")
    func longMessageStaysOneLine() throws {
        let short = try showHUD("已复制")
        let long = try showHUD(String(repeating: "很长的提示文案", count: 12))

        #expect(long.frame.height == short.frame.height)
    }
}
