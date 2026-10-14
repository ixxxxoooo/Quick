// SuperPanelActionListView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 上下文动作列表：单行紧凑行 + 右侧直达键帽
struct SuperPanelActionListView: View {

    let model: SuperPanelModel
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let preview = model.primaryPreview, preview.hasRichDetail {
                SuperPanelSpotlightCard(
                    preview: preview,
                    sourceText: model.sourceText,
                    onCopy: onCopy
                )
            }

            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                row(index: index, action: action)
            }

            if model.actions.isEmpty {
                SuperPanelEmptyState(icon: "tray", message: "没有可用的操作")
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    /// 第一行没有预览卡时，用识别出的答案当副标题（预览并入第一个动作）
    private func trailingText(index: Int, action: SuperPanelAction) -> String {
        if index == 0, let preview = model.primaryPreview, !preview.hasRichDetail {
            return preview.headline
        }
        return action.subtitle
    }

    private func row(index: Int, action: SuperPanelAction) -> some View {
        let isSelected = model.selectedIndex == index

        return Button {
            action.execute()
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: action.icon)
                    .font(DesignTokens.Typography.inlineIcon)
                    .foregroundStyle(
                        isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.progress
                    )
                    .frame(width: DesignTokens.Size.rowIcon, height: DesignTokens.Size.rowIcon)

                Text(action.title)
                    .font(DesignTokens.Typography.rowTitle)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)

                Text(trailingText(index: index, action: action))
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                SuperPanelKeycap(label: SuperPanelKeys.label(at: index), highlighted: isSelected)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .fill(isSelected ? DesignTokens.Colors.selection : Color.clear)
            )
            // 命中区域覆盖整个按钮：未选中时底色是透明的，透明区域默认点不到
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .onHover { hovering in
            if hovering { model.selectedIndex = index }
        }
    }
}
