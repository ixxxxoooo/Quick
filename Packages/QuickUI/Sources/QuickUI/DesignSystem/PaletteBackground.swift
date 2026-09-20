// PaletteBackground.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 面板背景
///
/// 和 Tinycast 的 `PaletteBackground` 一致，分三层：
/// 1. 原生 vibrancy（`NSVisualEffectView`）做真实的背景模糊
/// 2. scrim 压暗，保证上面放 20pt 文字仍然可读
/// 3. 极淡的边缘高光，让无边框面板在浅色壁纸上也有边界
///
/// **这里没有投影，这是有意的。** 面板投影由 AppKit 的窗口阴影提供
/// （`PalettePanel.hasShadow = true`）：窗口阴影绘制在窗口之外，形状直接取自窗口的
/// alpha 通道，所以圆角就是圆角。若在这里再叠一层 SwiftUI `.shadow`，阴影会被窗口
/// 边界裁切，在圆角外侧的方形三角区留下不透明的暗块 —— 看起来就是「圆角外面多了
/// 一层方角」；而且它会把窗口 alpha 撑成方形，连带把 AppKit 的窗口阴影也变成方角。
public struct PaletteBackground: View {

    /// 边缘高光要用物理像素宽度，否则 2x 屏上是 2px 的粗边
    @Environment(\.displayScale) private var displayScale

    public init() {}

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)

        DesignTokens.Colors.panelScrim
            .background(VisualEffectView())
            .overlay {
                shape
                    .strokeBorder(
                        DesignTokens.Colors.panelEdgeGradient,
                        lineWidth: DesignTokens.Size.hairline / displayScale
                    )
                    // 边框只是装饰，不该吃掉面板上的点击
                    .allowsHitTesting(false)
            }
    }
}
