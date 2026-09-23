// SuperPanelDockView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 工作台：常用工具 + 最近使用 + 剪贴板预览（对齐 Fasty SuperPanelDockView）
struct SuperPanelDockView: View {

    let model: SuperPanelModel
    @Binding var hoveredID: String?
    let onLaunchTool: (SuperPanelQuickTool) -> Void
    let onRecentItem: (SuperPanelRecentItem) -> Void
    let onReplaceWithClipboard: (String) -> Void
    let onCopyClipboard: (String) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.sm), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if !model.quickTools.isEmpty {
                quickTools
            }

            if model.showRecents, !model.recentItems.isEmpty {
                recents
            }

            if model.showClipboard, !model.latestClipboard.isEmpty {
                clipboardCard
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.lg)
    }

    private var quickTools: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            sectionTitle("常用工具")

            LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.sm) {
                ForEach(Array(model.quickTools.enumerated()), id: \.element.id) { index, tool in
                    toolCard(index: index, tool: tool)
                }
            }
        }
    }

    private func toolCard(index: Int, tool: SuperPanelQuickTool) -> some View {
        let isSelected = model.selectedIndex == index
        let isHovered = hoveredID == tool.id

        return Button {
            onLaunchTool(tool)
        } label: {
            VStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: tool.icon)
                    .font(DesignTokens.Typography.iconGlyph)
                    .foregroundStyle(DesignTokens.Colors.progress)
                    .frame(
                        width: DesignTokens.Size.rowIcon + DesignTokens.Spacing.lg,
                        height: DesignTokens.Size.rowIcon + DesignTokens.Spacing.lg
                    )
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                            .fill(DesignTokens.Colors.progress.opacity(0.10))
                    )
                Text(tool.title)
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(
                        isSelected || isHovered
                            ? DesignTokens.Colors.selection : DesignTokens.Colors.cardFill)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredID = tool.id
                model.selectedIndex = index
            } else if hoveredID == tool.id {
                hoveredID = nil
            }
        }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            sectionTitle("最近使用")

            ForEach(model.recentItems) { item in
                Button {
                    onRecentItem(item)
                } label: {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        Image(systemName: item.icon)
                            .font(DesignTokens.Typography.inlineIcon)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .frame(width: DesignTokens.Size.rowIcon, height: DesignTokens.Size.rowIcon)
                        Text(item.title)
                            .font(DesignTokens.Typography.rowTitle)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: DesignTokens.Spacing.sm)
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(DesignTokens.Typography.rowTrailing)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.right")
                            .font(DesignTokens.Typography.compactIcon)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                            .fill(hoveredID == item.id ? DesignTokens.Colors.rowHover : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredID = hovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
                }
            }
        }
    }

    private var clipboardCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "doc.on.clipboard")
                        .font(DesignTokens.Typography.compactIcon)
                    Text("最近剪贴板")
                        .font(DesignTokens.Typography.compactKeyCap)
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)

                Spacer(minLength: DesignTokens.Spacing.sm)

                Button {
                    onCopyClipboard(model.latestClipboard)
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        Image(systemName: "doc.on.doc")
                            .font(DesignTokens.Typography.compactIcon)
                        Text("复制")
                            .font(DesignTokens.Typography.compactKeyCap)
                    }
                    .foregroundStyle(DesignTokens.Colors.progress)
                }
                .buttonStyle(.plain)
            }

            Button {
                onReplaceWithClipboard(model.latestClipboard)
            } label: {
                Text(model.latestClipboard)
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("点击把这条剪贴板内容替换回原处")
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.cardFill)
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DesignTokens.Typography.sectionHeader)
            .foregroundStyle(DesignTokens.Colors.textTertiary)
    }
}
