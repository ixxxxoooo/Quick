// SuperPanelHeaderView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 超级面板头部：上下文态与工作台态两种排布
struct SuperPanelHeaderView: View {

    let model: SuperPanelModel
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: DesignTokens.Spacing.sm) {
                if model.hasContext {
                    sourceBadge
                } else {
                    title
                }

                Spacer(minLength: DesignTokens.Spacing.sm)

                HStack(spacing: DesignTokens.Spacing.xs) {
                    iconButton("gearshape", help: "超级面板设置", action: onOpenSettings)
                    iconButton("xmark", help: "关闭", action: onClose)
                }
            }

            if model.hasContext {
                tabSegment
            }
        }
        .padding(.leading, DesignTokens.Spacing.lg)
        .padding(.trailing, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.separator)
                .frame(height: DesignTokens.Size.hairline)
        }
    }

    private var sourceBadge: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: model.primaryPreview?.icon ?? "text.cursor")
                .font(DesignTokens.Typography.compactIcon)
            Text(model.primaryPreview?.title ?? "选中文本")
                .font(DesignTokens.Typography.compactKeyCap)
                .lineLimit(1)
        }
        .foregroundStyle(DesignTokens.Colors.progress)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                .fill(DesignTokens.Colors.progress.opacity(DesignTokens.Opacity.tint))
        )
    }

    private var tabSegment: some View {
        HStack(spacing: DesignTokens.Spacing.hairline) {
            ForEach(SuperPanelTab.allCases) { tab in
                Button {
                    model.select(tab)
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: tab.icon)
                            .font(DesignTokens.Typography.compactIcon)
                        Text(tab.rawValue)
                            .font(DesignTokens.Typography.compactKeyCap)
                    }
                    .foregroundStyle(
                        model.activeTab == tab
                            ? DesignTokens.Colors.textPrimary
                            : DesignTokens.Colors.textSecondary
                    )
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.menu, style: .continuous)
                            .fill(
                                model.activeTab == tab
                                    ? DesignTokens.Colors.selection
                                    : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(DesignTokens.Spacing.hairline)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.menu + 1, style: .continuous)
                .fill(DesignTokens.Colors.controlSurface)
        )
    }

    private var title: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(DesignTokens.Typography.inlineIcon)
                .foregroundStyle(DesignTokens.Colors.progress)
            Text("超级面板")
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text(SuperPanelTab.dock.rawValue)
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(DesignTokens.Colors.progress)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                        .fill(DesignTokens.Colors.progress.opacity(DesignTokens.Opacity.tint))
                )
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(DesignTokens.Typography.compactIcon)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(
                    width: DesignTokens.Size.windowControlButton,
                    height: DesignTokens.Size.windowControlButton
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }
}
