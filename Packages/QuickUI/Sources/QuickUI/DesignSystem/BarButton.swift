// BarButton.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 栏位按钮
///
/// 悬停时出现胶囊底，用在面板底栏与窗口标题栏这两处「栏位」上。
/// 两种样式各自固定尺寸（`.titled` 用 `Size.barButtonHeight`、`.icon` 用
/// `Size.windowControlButton`），这样同一排按钮的基线永远对齐。
public struct BarButton: View {

    /// 按钮样式
    public enum Style {
        /// 图标 + 文字 —— 底栏用
        case titled
        /// 只有图标，方形 —— 窗口标题栏用；此时 `title` 只作无障碍标签，必须写清动作
        case icon
    }

    /// 语义色调
    public enum Tone {
        case normal
        /// 破坏性动作（关闭窗口）：悬停时转成红底红图标
        case destructive
    }

    public let title: String
    public let icon: String?
    public let style: Style
    public let isActive: Bool
    public let tone: Tone
    public let action: () -> Void

    @State private var isHovered = false

    /// 初始化栏位按钮
    /// - Parameters:
    ///   - title: 按钮文字；`.icon` 样式下它是无障碍标签
    ///   - icon: 可选 SF Symbol 名
    ///   - style: 样式（`.titled` / `.icon`）
    ///   - isActive: 开关型按钮的激活态（例如「窗口置顶」已打开）
    ///   - tone: 语义色调
    ///   - action: 点击动作
    public init(
        title: String,
        icon: String? = nil,
        style: Style = .titled,
        isActive: Bool = false,
        tone: Tone = .normal,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isActive = isActive
        self.tone = tone
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(foreground)
                .background {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                        .fill(fill)
                }
                // 命中区域必须覆盖整个按钮，否则只有图标/文字本身可点。
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .onHover { hovering in
            withAnimation(.easeOut(duration: DesignTokens.Duration.hover)) {
                isHovered = hovering
            }
        }
    }

    /// 按钮内容
    @ViewBuilder
    private var label: some View {
        switch style {
        case .titled:
            HStack(spacing: DesignTokens.Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(DesignTokens.Typography.iconGlyph)
                }
                Text(title)
                    .font(DesignTokens.Typography.bar)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(height: DesignTokens.Size.barButtonHeight)

        case .icon:
            Image(systemName: icon ?? "questionmark")
                .font(DesignTokens.Typography.windowControlIcon)
                .frame(
                    width: DesignTokens.Size.windowControlButton,
                    height: DesignTokens.Size.windowControlButton
                )
        }
    }

    /// 图标 / 文字颜色
    ///
    /// 激活态与破坏性悬停沿用胶囊那两个开关型令牌：它们本来就是「置顶这类开关按钮的激活色」
    /// 与「关闭按钮的悬停色」，两处窗口控制按钮共用一套颜色才不会各说各话。
    private var foreground: Color {
        if isActive { return DesignTokens.Colors.capsuleToggleGlyph }
        if tone == .destructive, isHovered { return DesignTokens.Colors.capsuleCloseGlyph }
        return DesignTokens.Colors.textSecondary
    }

    /// 底色
    private var fill: Color {
        if isActive { return DesignTokens.Colors.capsuleToggleFill }
        guard isHovered else { return .clear }
        return tone == .destructive
            ? DesignTokens.Colors.capsuleCloseFill : DesignTokens.Colors.rowHover
    }
}
