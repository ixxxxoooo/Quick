// ClipboardListView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 剪贴板历史列表视图
struct ClipboardListView: View {

    let store: ClipboardStore

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // 筛选栏
            HStack {
                Text("剪贴板历史")
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Button("清空") {
                    store.clearHistory()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .font(DesignTokens.Typography.rowTrailing)
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.md)

            // 条目列表
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xxs) {
                    ForEach(store.search(searchText)) { entry in
                        ClipboardRowView(entry: entry) {
                            EventBus.shared.post(CopyToClipboardEvent(text: entry.text))
                            EventBus.shared.post(HidePaletteEvent())
                        } onToggleFavorite: {
                            store.toggleFavorite(entry.id)
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
            }
        }
    }
}

/// 剪贴板条目行视图
struct ClipboardRowView: View {
    let entry: ClipboardEntry
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: entry.type.icon)
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.preview)
                    .font(DesignTokens.Typography.rowTitle)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)

                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Spacer()

            if entry.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                .fill(isHovered ? DesignTokens.Colors.rowHover : .clear)
        }
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
        .contentShape(Rectangle())
        .contextMenu {
            Button("收藏") { onToggleFavorite() }
            Button("删除") { /* TODO */  }
        }
    }
}
