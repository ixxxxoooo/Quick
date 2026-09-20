// PaletteRootView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 面板根视图
///
/// 面板外壳。结构与参考实现一致：**没有分隔线，也没有通栏底栏** ——
/// header 和底栏都是用 `safeAreaInset` 挂在滚动内容上的，内容从它们下面穿过，
/// 靠 `edgeDissolve()` 淡出。
///
/// ```
/// ┌────────────────────────────────────────────────┐
/// │  [icon] 搜索框                          [状态]  │  header（无背景、无分隔线）
/// │                                                  │
/// │   结果行从 header 下面穿过并淡出                  │
/// │                                                  │
/// │  计数                              ( 打开  ↵ )   │  浮动胶囊，无通栏
/// └────────────────────────────────────────────────┘
/// ```
///
/// 为什么用 `safeAreaInset` 而不是把栏位当兄弟节点：兄弟节点会把滚动区**硬切**在栏位边缘，
/// 滚动时能看到行被齐刷刷切断；`safeAreaInset` 让内容从栏位下面穿过去，
/// 静止时贴边、滚动时渐隐，这是参考实现的做法。
///
/// 查询状态放在本视图的 `@State` 中，**不观察持有 `NSPanel` 的协调器** ——
/// 观察它会让 SwiftUI 与 AttributeGraph 进入重建死循环，CPU 打满。
/// 详见 PaletteCoordinator 顶部的说明。
struct PaletteRootView: View {

    /// 执行搜索（由协调器注入）
    var searchHandler: (String) async -> [SearchableItem]

    /// 初始查询
    var initialQuery: String = ""

    @State private var query: String = ""
    @State private var results: [SearchableItem] = []
    @State private var selectedIndex: Int = 0
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private let log = QuickLog.palette

    /// 搜索防抖时长
    ///
    /// 太短会把每次按键都变成一次全模块并发扫描，太长则输入有顿挫感。
    private static let searchDebounce = Duration.milliseconds(80)

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .frame(
                width: DesignTokens.Size.panelWidth,
                height: DesignTokens.Size.panelHeight
            )
            .background(PaletteBackground())
            // 不要在这里加 .shadow：面板投影由 AppKit 的窗口阴影负责，见 PaletteBackground 的说明。
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous))
            .onAppear {
                if !initialQuery.isEmpty { query = initialQuery }
                log.debug("面板视图已出现，开始首次搜索")
                runSearch(query)
            }
            .onChange(of: query) { _, newValue in
                runSearch(newValue)
            }
    }

    // MARK: - 头部

    /// 搜索栏
    ///
    /// 没有背景、没有下分隔线：它只是浮在内容上方，内容从它下面穿过。
    /// 高度恒定，所以输入时搜索栏不会位移。
    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            SearchFieldView(
                query: $query,
                placeholder: "搜索应用、命令和工具…",
                icon: "magnifyingglass"
            )

            trailingAccessory
        }
        .padding(.leading, DesignTokens.Spacing.md + DesignTokens.Spacing.lg)
        .padding(.trailing, DesignTokens.Spacing.xl)
        .padding(.top, DesignTokens.Size.headerPadding)
        .frame(height: DesignTokens.Size.headerHeight + DesignTokens.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    /// 搜索栏右侧的状态槽位
    ///
    /// 宽度固定，所以「搜索中」与「有内容」两种状态下输入框不会位移。
    @ViewBuilder
    private var trailingAccessory: some View {
        Group {
            if isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.iconGlyph)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
            }
        }
        .frame(width: DesignTokens.Size.headerIconSlot)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if results.isEmpty && !query.isEmpty && !isSearching {
            emptyState(
                icon: "questionmark.circle",
                message: "没有找到结果",
                detail: "换个关键词试试，或检查对应模块是否已启用"
            )
        } else if results.isEmpty && query.isEmpty && !isSearching {
            emptyState(
                icon: "magnifyingglass",
                message: "开始输入以搜索",
                detail: "应用、命令、公式与工具都可以直接搜"
            )
        } else {
            ResultListView(items: results, selectedIndex: $selectedIndex)
        }
    }

    /// 空状态
    ///
    /// 两种空状态共用同一个形状：一个图标 + 一句说明 + 一行提示。
    /// 空着一片什么都不显示是最糟的处理方式 —— 用户分不清是没结果还是坏了。
    private func emptyState(icon: String, message: String, detail: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Text(message)
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(detail)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底栏

    /// 底栏
    ///
    /// 没有通栏背景、没有上分隔线：左侧是结果计数，右侧是一枚浮起的玻璃胶囊。
    /// 行的内容从这一带下面穿过，由 `edgeDissolve()` 淡出。
    private var bottomBar: some View {
        HStack(spacing: 0) {
            Text(statusText)
                .font(DesignTokens.Typography.bar)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .lineLimit(1)

            Spacer(minLength: DesignTokens.Spacing.md)

            if !results.isEmpty {
                primaryActionPill
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: DesignTokens.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }

    /// 主操作胶囊：动作名 + 键位
    private var primaryActionPill: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text("打开")
                .font(DesignTokens.Typography.bar)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            KeyCapChip(text: "↵", style: .outline, scale: .compact)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: DesignTokens.Size.barButtonHeight)
        .frosted(in: Capsule())
    }

    /// 底栏左侧的状态文本
    private var statusText: String {
        if isSearching { return "搜索中…" }
        if results.isEmpty { return "无结果" }
        return "\(selectedIndex + 1) / \(results.count)"
    }

    // MARK: - 搜索

    /// 发起搜索（带去抖与取消）
    ///
    /// 每次输入都会取消上一次未完的搜索 —— 否则快速输入会堆积起多个
    /// 全模块并发扫描，最后一个先返回还会覆盖掉正确结果。
    private func runSearch(_ text: String) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled else { return }

            isSearching = true
            let items = await searchHandler(text)
            guard !Task.isCancelled else { return }

            results = items
            selectedIndex = 0
            isSearching = false
        }
    }
}
