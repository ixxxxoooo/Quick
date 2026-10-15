// SuperPanelDockView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 工作台：常用工具网格 + 最近使用 + 剪贴板预览（对齐 Fasty SuperPanelDockView）
///
/// 键盘可以走完整个工作台：工具网格用四向键，往下走出网格就进入「最近使用」；
/// 选中序号跨两段连续编号，见 `SuperPanelDockNavigator`。
struct SuperPanelDockView: View {

    let model: SuperPanelModel
    let onLaunchTool: (SuperPanelQuickTool) -> Void
    let onRecentItem: (SuperPanelRecentItem) -> Void
    let onReplaceWithClipboard: (String) -> Void
    let onCopyClipboard: (String) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.xs),
        count: SuperPanelModel.dockColumns)

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if !model.quickTools.isEmpty {
                quickTools
            }

            if !model.visibleRecents.isEmpty {
                recents
            }

            if model.showClipboard, !model.latestClipboard.isEmpty {
                clipboardCard
            }

            if model.quickTools.isEmpty, model.visibleRecents.isEmpty,
                !(model.showClipboard && !model.latestClipboard.isEmpty)
            {
                SuperPanelEmptyState(icon: "square.grid.2x2", message: "工作台是空的，可在设置里添加常用工具")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private var quickTools: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            sectionTitle("常用工具")

            LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.xs) {
                ForEach(Array(model.quickTools.enumerated()), id: \.element.id) { index, tool in
                    toolCard(index: index, tool: tool)
                }
            }
        }
    }

    private func toolCard(index: Int, tool: SuperPanelQuickTool) -> some View {
        let isSelected = model.selectedIndex == index

        return Button {
            onLaunchTool(tool)
        } label: {
            VStack(spacing: DesignTokens.Spacing.xxs) {
                Image(systemName: tool.icon)
                    .font(DesignTokens.Typography.inlineIcon)
                    .foregroundStyle(isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.progress)
                    .frame(width: DesignTokens.Size.rowIcon, height: DesignTokens.Size.rowIcon)
                Text(tool.title)
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(isSelected ? DesignTokens.Colors.selection : DesignTokens.Colors.cardFill)
            )
            .overlay(alignment: .topTrailing) {
                if let label = SuperPanelKeys.label(at: index) {
                    Text(label)
                        .font(DesignTokens.Typography.compactKeyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(DesignTokens.Spacing.xs)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("打开 \(tool.title)")
        .onHover { hovering in
            if hovering { model.selectedIndex = index }
        }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("最近使用")
                .padding(.bottom, DesignTokens.Spacing.xxs)

            ForEach(Array(model.visibleRecents.enumerated()), id: \.element.id) { offset, item in
                recentRow(index: model.quickTools.count + offset, item: item)
            }
        }
    }

    private func recentRow(index: Int, item: SuperPanelRecentItem) -> some View {
        let isSelected = model.selectedIndex == index

        return Button {
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
                    .layoutPriority(1)
                Text(item.subtitle ?? "")
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                SuperPanelKeycap(label: SuperPanelKeys.label(at: index), highlighted: isSelected)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .fill(isSelected ? DesignTokens.Colors.selection : Color.clear)
            )
            // 未选中时底色是透明的，没有这句整行只有文字和图标可点
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("打开「\(item.title)」")
        .onHover { hovering in
            if hovering { model.selectedIndex = index }
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
                .help("复制剪贴板内容")
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
            .padding(.horizontal, DesignTokens.Spacing.xs)
    }
}
