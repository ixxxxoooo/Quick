// ActionMenuView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// ⌘K 操作菜单：贴在底栏上方的小浮层
///
/// 键盘（↑↓ ↵ Esc）由 `PaletteCoordinator` 在 AppKit 层路由进 `ActionMenuState`，
/// 这里只负责画出来，并支持鼠标悬停 / 点击。
struct ActionMenuView: View {

    var menu: ActionMenuState

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            ForEach(Array(menu.actions.enumerated()), id: \.element.id) { index, action in
                HStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: action.icon)
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .frame(width: DesignTokens.Size.menuIconSlot)
                    Text(action.title)
                        .font(DesignTokens.Typography.rowTitle)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Spacer(minLength: DesignTokens.Spacing.lg)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.menu, style: .continuous)
                        .fill(index == menu.index ? DesignTokens.Colors.selection : .clear)
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { menu.select(index) }
                }
                .onTapGesture {
                    menu.select(index)
                    menu.runSelected()
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(width: DesignTokens.Size.actionMenuWidth)
        .frosted(in: RoundedRectangle(cornerRadius: DesignTokens.Radius.menuPanel, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("操作菜单")
    }
}
