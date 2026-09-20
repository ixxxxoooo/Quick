// PaletteRootView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 面板根视图
///
/// 面板的顶层 SwiftUI 视图，包含搜索栏和结果列表。
/// 根据 PaletteCoordinator 的状态决定显示主搜索还是模块视图。
struct PaletteRootView: View {

    @State var coordinator: PaletteCoordinator

    /// 搜索结果
    @State private var results: [SearchableItem] = []

    /// 当前选中索引
    @State private var selectedIndex: Int = 0

    /// 是否正在搜索中
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            SearchFieldView(
                query: $coordinator.query,
                placeholder: coordinator.activeModuleID == nil
                    ? "搜索应用、命令和工具…"
                    : "搜索…",
                icon: coordinator.activeModuleID == nil
                    ? "magnifyingglass"
                    : "chevron.left"
            )
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.top, DesignTokens.Size.headerPadding)
            .padding(.bottom, DesignTokens.Spacing.md)

            Divider()
                .opacity(0.3)

            // 结果区域
            if results.isEmpty && !coordinator.query.isEmpty && !isSearching {
                emptyState
            } else {
                ResultListView(
                    items: results,
                    selectedIndex: $selectedIndex
                )
            }
        }
        .frame(
            width: DesignTokens.Size.panelWidth,
            height: DesignTokens.Size.panelHeight
        )
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.panel)
                .fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.panel))
        .shadow(color: .black.opacity(0.3), radius: 40, y: 10)
        .onChange(of: coordinator.query) { _, newValue in
            Task {
                isSearching = true
                results = await coordinator.search(query: newValue)
                selectedIndex = 0
                isSearching = false
            }
        }
    }

    /// 空状态视图
    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("没有找到结果")
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
