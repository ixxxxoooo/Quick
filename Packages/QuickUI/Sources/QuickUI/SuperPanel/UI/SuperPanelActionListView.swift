// SuperPanelActionListView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 上下文动作列表
struct SuperPanelActionListView: View {

    let model: SuperPanelModel
    @Binding var hoveredID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let preview = model.primaryPreview {
                SuperPanelSpotlightCard(preview: preview, sourceText: model.sourceText)
            }

            sectionTitle("操作")

            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                row(index: index, action: action)
            }

            if model.actions.isEmpty {
                Text("没有可用的操作")
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.xxl)
            }
        }
        .padding(.bottom, DesignTokens.Spacing.sm)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DesignTokens.Typography.sectionHeader)
            .foregroundStyle(DesignTokens.Colors.textTertiary)
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.top, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.xs)
    }

    private func row(index: Int, action: SuperPanelAction) -> some View {
        let isSelected = model.selectedIndex == index

        return Button {
            action.execute()
        } label: {
            HStack(spacing: DesignTokens.Spacing.lg) {
                indexBadge(index: index, highlighted: isSelected)

                Image(systemName: action.icon)
                    .font(DesignTokens.Typography.iconGlyph)
                    .foregroundStyle(
                        isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.progress
                    )
                    .frame(width: DesignTokens.Size.rowIcon, height: DesignTokens.Size.rowIcon)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(action.title)
                        .font(DesignTokens.Typography.rowTitle)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(action.subtitle)
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .fill(isSelected ? DesignTokens.Colors.selection : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .onHover { hovering in
            if hovering {
                hoveredID = action.id
                model.selectedIndex = index
            } else if hoveredID == action.id {
                hoveredID = nil
            }
        }
    }

    @ViewBuilder
    private func indexBadge(index: Int, highlighted: Bool) -> some View {
        if index < 9 {
            Text("\(index + 1)")
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(
                    highlighted ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary
                )
                .frame(width: DesignTokens.Size.compactKeyCap, height: DesignTokens.Size.compactKeyCap)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap, style: .continuous)
                        .fill(DesignTokens.Colors.controlSurface)
                )
        } else {
            Color.clear.frame(width: DesignTokens.Size.compactKeyCap, height: DesignTokens.Size.compactKeyCap)
        }
    }
}
