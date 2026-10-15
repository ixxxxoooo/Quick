// ActionPill.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 底栏动作胶囊的外观：文字 + 键帽，毛玻璃胶囊底
///
/// 主搜索列表右下角的「打开 ↵ / 操作 ⌘K」与各插件底栏的动作按钮共用它，
/// 外观只在这一处定义 —— 以前各插件自己拼一份（`controlSurface` 底、不同的间距），
/// 同一个位置的按钮在不同页面长得不一样。
public struct ActionPillLabel: View {

    public let title: String
    public let keyCap: String

    public init(title: String, keyCap: String) {
        self.title = title
        self.keyCap = keyCap
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(DesignTokens.Typography.bar)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            KeyCapChip(text: keyCap, style: .outline, scale: .compact)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: DesignTokens.Size.barButtonHeight)
        .frosted(in: Capsule())
        // 命中区域覆盖整个胶囊，而不只是文字与键帽
        .contentShape(Capsule())
    }
}

/// 可点击的底栏动作胶囊
public struct ActionPillButton: View {

    public let title: String
    public let keyCap: String
    public let action: () -> Void

    public init(title: String, keyCap: String, action: @escaping () -> Void) {
        self.title = title
        self.keyCap = keyCap
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ActionPillLabel(title: title, keyCap: keyCap)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// 插件底栏：右对齐的动作胶囊，不带背景
///
/// 背景交给面板本身 —— 底栏单独铺一层底色会在玻璃面板上切出一条色带（见 docs/ui.md）。
public struct ActionPillBar<Content: View>: View {

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Spacer(minLength: 0)
            content
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: DesignTokens.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }
}
