// BarButton.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 底栏按钮
///
/// 悬停时出现胶囊底，用于面板底栏的动作入口。
/// 高度固定在 `Size.barButtonHeight`，这样一排按钮的基线永远对齐。
public struct BarButton: View {

    public let title: String
    public let icon: String?
    public let action: () -> Void

    @State private var isHovered = false

    /// 初始化底栏按钮
    /// - Parameters:
    ///   - title: 按钮文字
    ///   - icon: 可选 SF Symbol 名
    ///   - action: 点击动作
    public init(title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(DesignTokens.Typography.iconGlyph)
                }
                Text(title)
                    .font(DesignTokens.Typography.bar)
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(height: DesignTokens.Size.barButtonHeight)
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                    .fill(isHovered ? DesignTokens.Colors.rowHover : .clear)
            }
            // 命中区域必须覆盖整个胶囊，否则只有文字可点。
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: DesignTokens.Duration.hover)) {
                isHovered = hovering
            }
        }
    }
}
