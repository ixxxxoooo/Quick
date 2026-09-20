// PluginHeaderView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 插件模式下的面板头部
///
/// 替换搜索模式下的搜索框，显示返回按钮、插件图标与名称、分离按钮。
/// 布局与搜索栏高度对齐，确保切换时不产生跳变。
struct PluginHeaderView: View {

    /// 插件显示名称
    let pluginName: String

    /// 插件图标（SF Symbol 名称）
    let pluginIcon: String

    /// 返回按钮回调
    let onBack: () -> Void

    /// 分离按钮回调
    let onDetach: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            backButton
            pluginInfo
            Spacer()
            detachButton
        }
        .padding(.leading, DesignTokens.Spacing.md + DesignTokens.Spacing.lg)
        .padding(.trailing, DesignTokens.Spacing.xl)
        .padding(.top, DesignTokens.Size.headerPadding)
        .frame(height: DesignTokens.Size.pluginHeaderHeight + DesignTokens.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    /// 返回按钮
    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(
                    width: DesignTokens.Size.pluginBackButton,
                    height: DesignTokens.Size.pluginBackButton
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回搜索")
    }

    /// 插件图标 + 名称
    private var pluginInfo: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: pluginIcon)
                .font(.system(size: DesignTokens.Size.pluginHeaderIcon, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(pluginName)
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
                    width: DesignTokens.Size.pluginBackButton,
                    height: DesignTokens.Size.pluginBackButton
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("分离为独立窗口")
        .help("分离为独立窗口 (⌘D)")
    }
}
