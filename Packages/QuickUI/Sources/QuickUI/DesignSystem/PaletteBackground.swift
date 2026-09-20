// PaletteBackground.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 面板背景
///
/// 三层的叠加，缺一层在某种壁纸下就会出问题：
/// 1. 系统材质提供真实的背景模糊（不是假毛玻璃）
/// 2. scrim 压暗，保证在上面放 20pt 文字仍然可读
/// 3. 边缘高光，让无边框面板在浅色壁纸上有边界
///
/// 面板内容**只应该**通过这个视图取背景，不要在别处重复写这三层配置。
public struct PaletteBackground: View {

    public init() {}

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)

        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(DesignTokens.Colors.panelScrim)
            }
            .overlay {
                shape
                    .strokeBorder(
                        DesignTokens.Colors.panelEdgeGradient, lineWidth: DesignTokens.Size.hairline)
            }
    }
}
