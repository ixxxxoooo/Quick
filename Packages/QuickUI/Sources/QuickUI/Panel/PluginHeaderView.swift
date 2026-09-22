// PluginHeaderView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 插件模式下的面板头部
///
/// 替换搜索模式下的搜索框，显示返回按钮、插件图标与名称、分离按钮。
/// 布局与搜索栏高度对齐，确保切换时不产生跳变。
///
/// 声明了 `supportsPanelSearch` 的插件，中间用**插件内搜索框**替换插件名 —— 文本经
/// `PluginSearchQuery` 交给插件视图自行过滤（对齐 Raycast：进入扩展后搜索栏一直在，
/// 由扩展决定怎么用）。
struct PluginHeaderView: View {

    /// 插件显示名称
    let pluginName: String

    /// 插件图标（SF Symbol 名称）
    let pluginIcon: String

    /// 插件内搜索状态；`nil` 表示该插件不提供插件内搜索
    let search: PluginSearchQuery?

    /// 返回按钮回调
    let onBack: () -> Void

    /// 分离按钮回调
    let onDetach: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            backButton

            if let search {
                SearchFieldView(
                    query: Binding(
                        get: { search.text },
                        set: { search.text = $0 }
                    ),
                    placeholder: "在 \(pluginName) 中搜索…",
                    // 子面板里不放搜索图标：返回按钮已经把这一行的视觉锚点占住了，
                    // 再加一个放大镜就是两个图标挤在一起抢注意力
                    icon: nil,
                    // 默认不抢焦点：焦点属于插件视图（方向键切换）。⌘F 才把焦点要过来
                    autoFocus: false,
                    focusTrigger: search.focusToken
                )
            } else {
                pluginInfo

                // 没有搜索框时中间空白仍是窗口拖拽区（分离窗口同款做法）
                Spacer()
                    .background(WindowDragArea())
            }

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
