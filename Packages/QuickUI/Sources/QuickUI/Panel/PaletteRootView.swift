// PaletteRootView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 面板根视图
///
/// 面板外壳。支持两种模式：
///
/// **搜索模式**（默认）：搜索框 + 结果列表，与参考实现一致 ——
/// header 和底栏都是用 `safeAreaInset` 挂在滚动内容上的，内容从它们下面穿过，
/// 靠 `edgeDissolve()` 淡出。
///
/// **模块模式**：当用户选中一个模块后，切换到该模块的完整视图。
/// 头部变为返回按钮 + 模块名称 + 分离按钮，内容区显示模块的 `makeView()`。
///
/// ```
/// ┌──────────── 搜索模式 ─────────────┐  ┌──────────── 模块模式 ─────────────┐
/// │  [icon] 搜索框              [状态]  │  │  [<] [icon] 模块名称       [分离]  │
/// │                                     │  │                                    │
/// │   结果行从 header 下面穿过并淡出      │  │   模块的 makeView() 内容            │
/// │                                     │  │                                    │
/// │  计数                  ( 打开  ↵ )   │  │                                    │
/// └─────────────────────────────────────┘  └────────────────────────────────────┘
/// ```
///
/// 查询状态放在本视图的 `@State` 中，**不观察持有 `NSPanel` 的协调器** ——
/// 观察它会让 SwiftUI 与 AttributeGraph 进入重建死循环，CPU 打满。
/// 详见 PaletteCoordinator 顶部的说明。
struct PaletteRootView: View {

    /// 选中状态
    ///
    /// 由协调器提供，上下键在 AppKit 层（`PalettePanel.sendEvent`）驱动它 ——
    /// 焦点在搜索框里，SwiftUI 这一层收不到方向键。
    var selection: PaletteSelection

    /// 面板模式（搜索 vs 模块）
    ///
    /// 由协调器提供的 `@Observable` 桥接对象，不持有 NSPanel，安全观察。
    var paletteMode: PaletteMode

    /// 执行搜索（由协调器注入）
    var searchHandler: (String) async -> [SearchableItem]

    /// 获取模块视图（由协调器注入）
    ///
    /// 参数：(moduleID, context) -> 模块视图；返回 nil 表示模块不可用。
    var moduleViewProvider: (String, [String: String]) -> AnyView?

    /// 初始查询
    var initialQuery: String = ""

    @State private var query: String = ""
    @State private var results: [SearchableItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var appIndexSubscription: EventSubscription?

    private let log = QuickLog.palette

    /// 搜索防抖时长
    private static let searchDebounce = Duration.milliseconds(80)

    var body: some View {
        ZStack {
            if paletteMode.isModuleMode {
                moduleContent
            } else {
                searchContent
            }
        }
        .frame(
            width: DesignTokens.Size.panelWidth,
            height: DesignTokens.Size.panelHeight
        )
        .background(PaletteBackground())
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous))
        .onAppear {
            if !initialQuery.isEmpty { query = initialQuery }
            log.debug("面板视图已出现，开始首次搜索")
            runSearch(query)
            if appIndexSubscription == nil {
                appIndexSubscription = EventBus.shared.on(AppIndexRefreshedEvent.self) { _ in
                    Task { @MainActor in
                        if query.isEmpty {
                            runSearch("")
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if results.isEmpty && !paletteMode.isModuleMode {
                runSearch(query)
            }
        }
        .onChange(of: query) { _, newValue in
            runSearch(newValue)
        }
    }

    // MARK: - 搜索模式

    /// 搜索模式完整视图
    private var searchContent: some View {
        searchResultsArea
            .safeAreaInset(edge: .top, spacing: 0) { searchHeader }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    /// 搜索栏
    private var searchHeader: some View {
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

    /// 搜索结果区域
    @ViewBuilder
    private var searchResultsArea: some View {
        if results.isEmpty && !query.isEmpty && !isSearching {
            emptyState(
                icon: "questionmark.circle",
                message: "没有找到结果",
                detail: "换个关键词试试，或检查对应插件是否已启用"
            )
        } else if results.isEmpty && query.isEmpty {
            if isSearching {
                ProgressView("正在加载应用程序…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState(
                    icon: "magnifyingglass",
                    message: "暂无应用程序",
                    detail: "正在扫描系统应用，请稍候…"
                )
            }
        } else {
            ResultListView(
                items: results,
                selectedIndex: selectionBinding,
                selection: selection
            )
        }
    }

    /// 结果列表的选中下标绑定
    private var selectionBinding: Binding<Int> {
        Binding(
            get: { selection.index },
            set: { selection.index = $0 }
        )
    }

    /// 底栏
    private var bottomBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: DesignTokens.Spacing.md)

            if !results.isEmpty {
                primaryActionPill
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: DesignTokens.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }

    /// 主操作胶囊
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

    // MARK: - 模块模式

    /// 模块模式完整视图
    private var moduleContent: some View {
        VStack(spacing: 0) {
            ModuleHeaderView(
                moduleName: paletteMode.activeModuleName ?? "",
                moduleIcon: paletteMode.activeModuleIcon ?? "questionmark",
                onBack: {
                    paletteMode.popToRoot()
                },
                onDetach: {
                    guard let moduleID = paletteMode.activeModuleID else { return }
                    EventBus.shared.post(DetachPanelEvent(moduleID: moduleID))
                }
            )

            if let moduleID = paletteMode.activeModuleID,
                let moduleView = moduleViewProvider(moduleID, paletteMode.context)
            {
                moduleView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                emptyState(
                    icon: "exclamationmark.triangle",
                    message: "插件不可用",
                    detail: "该插件可能已被禁用或未安装"
                )
            }
        }
    }

    // MARK: - 空状态

    /// 空状态
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

    // MARK: - 搜索

    /// 发起搜索（带去抖与取消）
    private func runSearch(_ text: String) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled else { return }

            isSearching = true
            let items = await searchHandler(text)
            guard !Task.isCancelled else { return }

            results = items
            isSearching = false
            selection.update(count: items.count) { index in
                guard items.indices.contains(index) else { return }
                items[index].action()
            }
        }
    }
}
