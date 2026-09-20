// ModuleHeaderView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 模块模式下的面板头部
///
/// 替换搜索模式下的搜索框，显示返回按钮、模块图标与名称、分离按钮。
/// 布局与搜索栏高度对齐，确保切换时不产生跳变。
struct ModuleHeaderView: View {

    /// 模块显示名称
    let moduleName: String

    /// 模块图标（SF Symbol 名称）
    let moduleIcon: String

    /// 返回按钮回调
    let onBack: () -> Void

    /// 分离按钮回调
    let onDetach: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            backButton
            moduleInfo
            Spacer()
            detachButton
        }
        .padding(.leading, DesignTokens.Spacing.md + DesignTokens.Spacing.lg)
        .padding(.trailing, DesignTokens.Spacing.xl)
        .padding(.top, DesignTokens.Size.headerPadding)
        .frame(height: DesignTokens.Size.moduleHeaderHeight + DesignTokens.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    /// 返回按钮
    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(
                    width: DesignTokens.Size.moduleBackButton,
                    height: DesignTokens.Size.moduleBackButton
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回搜索")
    }

    /// 模块图标 + 名称
    private var moduleInfo: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: moduleIcon)
                .font(.system(size: DesignTokens.Size.moduleHeaderIcon, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(moduleName)
                .font(DesignTokens.Typography.panelTitle)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
        }
    }

    /// 分离窗口按钮
    private var detachButton: some View {
        Button(action: onDetach) {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(
                    width: DesignTokens.Size.moduleBackButton,
                    height: DesignTokens.Size.moduleBackButton
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("分离为独立窗口")
        .help("分离为独立窗口 (⌘D)")
    }
}
