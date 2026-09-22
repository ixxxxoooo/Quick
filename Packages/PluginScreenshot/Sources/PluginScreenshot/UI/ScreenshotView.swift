// ScreenshotView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// 截图插件视图
///
/// 面板里的四个入口：区域 / 全屏 / 窗口 / 贴图。真正的截图在有遮罩的浮层里完成，
/// 这里只负责把动作转出去。
struct ScreenshotView: View {

    let onArea: () -> Void
    let onFullScreen: () -> Void
    let onWindow: () -> Void
    let onPin: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            Image(systemName: "camera.viewfinder")
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Text("截图工具")
                .font(DesignTokens.Typography.panelTitle)

            HStack(spacing: DesignTokens.Spacing.xl) {
                entryButton("区域截图", icon: "rectangle.dashed", action: onArea)
                entryButton("全屏截图", icon: "rectangle.on.rectangle", action: onFullScreen)
                entryButton("窗口截图", icon: "macwindow", action: onWindow)
                entryButton("贴图", icon: "pin", action: onPin)
            }

            Spacer()

            Text("框选后可在原地标注：矩形、箭头、画笔、文字、马赛克、序号")
                .font(DesignTokens.Typography.keyCap)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func entryButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.iconGlyph)
                Text(label)
                    .font(DesignTokens.Typography.keyCap)
            }
            .frame(width: 120, height: 80)
            .background(DesignTokens.Colors.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        }
        .buttonStyle(.plain)
    }
}
