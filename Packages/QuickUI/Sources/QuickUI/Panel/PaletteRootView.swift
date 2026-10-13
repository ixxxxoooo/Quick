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
/// **插件模式**：当用户选中一个插件后，切换到该插件的完整视图。
/// 头部变为返回按钮 + 插件名称 + 分离按钮，内容区显示插件的 `makeView()`。
///
/// ```
/// ┌──────────── 搜索模式 ─────────────┐  ┌──────────── 插件模式 ─────────────┐
/// │  [icon] 搜索框              [状态]  │  │  [<] [icon] 插件名称       [分离]  │
/// │                                     │  │                                    │
/// │   结果行从 header 下面穿过并淡出      │  │   插件的 makeView() 内容            │
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

    /// ⌘K 操作菜单状态（由协调器提供，键盘路由在 AppKit 层）
    var actionMenu: ActionMenuState

    /// 搜索框文本（协调器与视图共用的唯一状态）
    ///
    /// 用桥接对象而不是 `@State`：协调器需要在面板外面改写它（自动粘贴、自动清空、
    /// `show(query:)` 预填），`@State` 做不到这件事。
    var paletteQuery: PaletteQuery

    /// 面板模式（搜索 vs 插件）
    ///
    /// 由协调器提供的 `@Observable` 桥接对象，不持有 NSPanel，安全观察。
    var paletteMode: PaletteMode

    /// 插件内搜索的桥接对象（由协调器提供）
    ///
    /// 只声明了 `supportsPanelSearch` 的插件才在头部显示搜索框；对象始终注入环境，
    /// 插件视图按需读取。
    var pluginSearch: PluginSearchQuery

    /// 执行搜索（由协调器注入）
    ///
    /// 返回 `PaletteSearchOutcome` 而不是裸数组：结果里带着「哪些插件超时了」，
    /// 面板才能把「没搜完」与「没找到」区分开告诉用户。
    var searchHandler: (String) async -> PaletteSearchOutcome

    /// 获取插件视图（由协调器注入）
    ///
    /// 参数：(pluginID, context) -> 插件视图；返回 nil 表示插件不可用。
    var pluginViewProvider: (String, [String: String]) -> AnyView?

    /// 某条结果被激活（由协调器注入，用于记录最近使用）
    var onItemActivated: ((String) -> Void)?

    /// 返回主搜索（由协调器注入）
    ///
    /// **不能在这里直接改 `paletteMode`**：协调器自己也存着「当前是哪个插件」，
    /// 绕过它会让两边状态不一致（返回之后协调器仍以为插件是激活的），
    /// 而且搜索框的焦点也没人负责还回去。
    var onReturnToSearch: () -> Void

    @State private var results: [SearchableItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var appIndexSubscription: EventSubscription?

    /// 上一次搜索里超时的插件数量
    ///
    /// 非零时结果列表下方会提示「部分插件未及时返回」—— 否则用户会把「没搜完」
    /// 当成「没找到」，而这两件事该做的下一步完全不同。
    @State private var timedOutPluginCount = 0

    private let log = QuickLog.palette

    /// 搜索防抖时长
    private static let searchDebounce = Duration.milliseconds(80)

    @AppStorage(SettingsKey.showResultIcons) private var showResultIcons = true
    @AppStorage(SettingsKey.showBottomBarHints) private var showBottomBarHints = true
    @AppStorage(SettingsKey.panelTransparency) private var panelTransparency = 0

    var body: some View {
        ZStack {
            if paletteMode.isPluginMode {
                pluginContent
            } else {
                searchContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaletteBackground(scrimBoost: Double(panelTransparency) / 100))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous))
        .onAppear {
            log.debug("面板视图已出现，开始首次搜索")
            runSearch(paletteQuery.text)
            if appIndexSubscription == nil {
                appIndexSubscription = EventBus.shared.on(AppIndexRefreshedEvent.self) { _ in
                    Task { @MainActor in
                        if paletteQuery.text.isEmpty {
                            runSearch("")
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if results.isEmpty && !paletteMode.isPluginMode {
                runSearch(paletteQuery.text)
            }
        }
        .onChange(of: paletteQuery.text) { oldValue, newValue in
            // 插件模式下不做粘贴检测和搜索：插件有自己的内容视图，
            // 在这里触发 NavigateEvent 会把 activePluginID 篡改成
            // json-formatter/sql-formatter，导致快捷键切换逻辑失效。
            guard !paletteMode.isPluginMode else { return }

            // 结果马上要换一批，菜单里指向的结果会失效
            actionMenu.close()

            // 粘贴检测：一次性增量超过阈值时检测内容类型
            let delta = newValue.count - oldValue.count
            if delta >= PasteContentDetector.pasteThreshold {
                let kind = PasteContentDetector.detect(newValue)
                switch kind {
                case .json:
                    log.notice("粘贴检测到 JSON 内容（长度 \(newValue.count, privacy: .public)），自动跳转 JSON 格式化")
                    EventBus.shared.post(
                        NavigateEvent(
                            pluginID: "json-formatter",
                            context: ["query": newValue]
                        ))
                    return
                case .sql:
                    log.notice("粘贴检测到 SQL 内容（长度 \(newValue.count, privacy: .public)），自动跳转 SQL 格式化")
                    EventBus.shared.post(
                        NavigateEvent(
                            pluginID: "sql-formatter",
                            context: ["query": newValue]
                        ))
                    return
                case .unknown:
                    break
                }
            }
            runSearch(newValue)
        }
    }

    // MARK: - 搜索模式

    /// 搜索模式完整视图
    private var searchContent: some View {
        searchResultsArea
            .safeAreaInset(edge: .top, spacing: 0) { searchHeader }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .overlay(alignment: .bottomTrailing) {
                if actionMenu.isOpen {
                    ActionMenuView(menu: actionMenu)
                        .padding(.trailing, DesignTokens.Spacing.md)
                        .padding(.bottom, DesignTokens.Size.bottomBarHeight)
                        .transition(.opacity)
                }
            }
    }

    /// 搜索栏
    private var searchHeader: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            SearchFieldView(
                query: Binding(
                    get: { paletteQuery.text },
                    set: { paletteQuery.text = $0 }),
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
            } else if !paletteQuery.text.isEmpty {
                Button {
                    // 查询的唯一真相是 paletteQuery：写它会经 onChange 触发重新搜索
                    paletteQuery.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.iconGlyph)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
                .help("清空搜索内容")
            }
        }
        .frame(width: DesignTokens.Size.headerIconSlot)
    }

    /// 搜索结果区域
    @ViewBuilder
    private var searchResultsArea: some View {
        if results.isEmpty && !paletteQuery.text.isEmpty && timedOutPluginCount > 0 {
            // 有插件超时且没有任何结果：这是「没搜完」，不是「没找到」。
            // 两者该做的下一步不同 —— 前者重试就好，后者要换关键词。
            emptyState(
                icon: "clock.badge.exclamationmark",
                message: "部分插件未及时返回",
                detail: "\(timedOutPluginCount) 个插件搜索超时，换个关键词或稍后重试"
            )
        } else if results.isEmpty && !paletteQuery.text.isEmpty && !isSearching {
            emptyState(
                icon: "questionmark.circle",
                message: "没有找到结果",
                detail: "换个关键词试试，或检查对应插件是否已启用"
            )
        } else if results.isEmpty && paletteQuery.text.isEmpty {
            // 不要整页 ProgressView：首次启动空查询通常几十毫秒内就有静态命令，
            // 整页转圈会被当成「卡死」。头部已有小指示器，这里只留轻量占位。
            emptyState(
                icon: "magnifyingglass",
                message: isSearching ? "正在准备…" : "暂无应用程序",
                detail: isSearching ? "首次启动会扫描应用，马上就好" : "正在扫描系统应用，请稍候…"
            )
        } else {
            VStack(spacing: 0) {
                ResultListView(
                    items: results,
                    selectedIndex: selectionBinding,
                    selection: selection,
                    showsIcons: showResultIcons,
                    query: paletteQuery.text,
                    showsQuickNumbers: true
                )
                if timedOutPluginCount > 0 {
                    timedOutNotice
                }
            }
        }
    }

    /// 结果不完整时的底注
    ///
    /// 有结果时不能整块换成空状态 —— 已有的结果仍然可用，只需要说明它不完整。
    private var timedOutNotice: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(DesignTokens.Typography.rowTrailing)
            Text("\(timedOutPluginCount) 个插件未及时返回")
                .font(DesignTokens.Typography.rowTrailing)
            Spacer(minLength: 0)
        }
        .foregroundStyle(DesignTokens.Colors.textTertiary)
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm)
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
            if !results.isEmpty {
                // 总数放左侧：让人知道列表滚下去还有多少，而不是只看到当前一屏
                Text("\(results.count) 个结果")
                    .font(DesignTokens.Typography.bar)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(.leading, DesignTokens.Spacing.md)
                    .accessibilityLabel("共 \(results.count) 个结果")
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            if showBottomBarHints && !results.isEmpty {
                primaryActionPill
                actionsPill
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: DesignTokens.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }

    /// 主操作胶囊：点击等同于按 ↵，执行当前选中项
    private var primaryActionPill: some View {
        ActionPillButton(title: "打开", keyCap: "↵") {
            selection.activate?(selection.index)
        }
    }

    /// 「操作」胶囊：提示 ⌘K 可以打开更多操作，也可以直接点
    private var actionsPill: some View {
        ActionPillButton(title: "操作", keyCap: "⌘K") {
            if actionMenu.isOpen {
                actionMenu.close()
            } else {
                openActionMenuFromPill()
            }
        }
        .padding(.leading, DesignTokens.Spacing.sm)
        .accessibilityLabel("打开操作菜单")
    }

    /// 从胶囊点开菜单：与 ⌘K 同一条路径（选中项 + 执行回调）
    private func openActionMenuFromPill() {
        guard let item = selection.selectedItem else { return }
        let index = selection.index
        actionMenu.open(
            actions: ResultActionCatalog.makeActions(for: item) {
                selection.activate?(index)
            })
    }

    // MARK: - 插件模式

    /// 插件模式完整视图
    private var pluginContent: some View {
        VStack(spacing: 0) {
            PluginHeaderView(
                pluginName: paletteMode.activePluginName ?? "",
                pluginIcon: paletteMode.activePluginIcon ?? "questionmark",
                search: paletteMode.activePluginSupportsSearch ? pluginSearch : nil,
                onBack: onReturnToSearch,
                onDetach: {
                    guard let pluginID = paletteMode.activePluginID else { return }
                    EventBus.shared.post(DetachPanelEvent(pluginID: pluginID))
                }
            )

            if let pluginID = paletteMode.activePluginID,
                let pluginView = pluginViewProvider(pluginID, paletteMode.context)
            {
                pluginView
                    .environment(\.pluginContext, paletteMode.context)
                    .environment(pluginSearch)
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
        // 面板是浮窗，打开插件时系统会把初始焦点给到第一个可聚焦控件
        // （常是某个工具栏按钮），随即顶着一圈焦点环。焦点本身保留，只不画环。
        .focusEffectDisabled()
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

            // 延迟挂上「搜索中」：空查询的静态命令通常瞬间返回，立刻转圈会闪一下
            let showSpinner = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                isSearching = true
            }
            let outcome = await searchHandler(text)
            showSpinner.cancel()
            guard !Task.isCancelled else { return }

            results = outcome.items
            selection.items = outcome.items
            timedOutPluginCount = outcome.timedOutPluginIDs.count
            isSearching = false
            selection.update(count: outcome.items.count) { index in
                guard outcome.items.indices.contains(index) else { return }
                // 记在动作之前：动作可能切走插件、甚至关掉面板
                onItemActivated?(outcome.items[index].id)
                outcome.items[index].action()
            }
        }
    }
}
