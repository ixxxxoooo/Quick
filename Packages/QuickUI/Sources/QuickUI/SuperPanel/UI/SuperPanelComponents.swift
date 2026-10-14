// SuperPanelComponents.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 直达键帽：行 / 卡片右侧的小方块，告诉用户按哪个键直接执行
struct SuperPanelKeycap: View {

    let label: String?
    let highlighted: Bool

    var body: some View {
        if let label {
            Text(label)
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(
                    highlighted ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary
                )
                .frame(width: DesignTokens.Size.compactKeyCap, height: DesignTokens.Size.compactKeyCap)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap, style: .continuous)
                        .fill(DesignTokens.Colors.controlSurface)
                )
        } else {
            // 超出键位表的条目不画键帽，但占位保持列对齐
            Color.clear.frame(width: DesignTokens.Size.compactKeyCap, height: DesignTokens.Size.compactKeyCap)
        }
    }
}

/// 空状态：一个图标加一句话，替代孤零零的灰字
struct SuperPanelEmptyState: View {

    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.iconGlyph)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(message)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.xxl)
    }
}

/// 骨架：内容识别期间先把面板的形状摆出来，识别完成后原地替换
///
/// 唤出要先抓选区（合成 ⌘C，耗时不定），如果等抓完才出现，用户会觉得「按了没反应」。
struct SuperPanelSkeleton: View {

    private let rowCount = 3

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(0..<rowCount, id: \.self) { _ in
                HStack(spacing: DesignTokens.Spacing.md) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap, style: .continuous)
                        .fill(DesignTokens.Colors.controlSurface)
                        .frame(width: DesignTokens.Size.rowIcon, height: DesignTokens.Size.rowIcon)
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap, style: .continuous)
                        .fill(DesignTokens.Colors.controlSurface)
                        .frame(height: DesignTokens.Size.compactKeyCap)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .accessibilityLabel("正在识别内容")
    }
}
