// SearchFieldView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 统一搜索输入框组件
///
/// 面板顶部的搜索栏，包含图标和文本输入框。
/// 所有模块在面板中都复用此组件。
///
/// **键盘导航不在这里。** 上下键与回车由 `PalettePanel.sendEvent` 在 AppKit 层拦截：
/// 面板打开时焦点在这个输入框里，field editor 会先把上下键拿去移动光标、
/// 把回车当成提交，挂在 SwiftUI 这一层的 `onKeyPress` 收不到事件。
public struct SearchFieldView: View {

    /// 搜索文本（双向绑定）
    @Binding public var query: String

    /// 占位文本
    public let placeholder: String

    /// 左侧图标（SF Symbol 名称）
    public let icon: String

    /// 初始化搜索输入框
    /// - Parameters:
    ///   - query: 搜索文本绑定
    ///   - placeholder: 占位文本
    ///   - icon: 左侧图标
    public init(
        query: Binding<String>,
        placeholder: String = "搜索…",
        icon: String = "magnifyingglass"
    ) {
        self._query = query
        self.placeholder = placeholder
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.headerIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: DesignTokens.Size.headerIconSlot)
                .accessibilityHidden(true)

            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.searchField)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .frame(height: DesignTokens.Size.headerHeight)
    }
}
