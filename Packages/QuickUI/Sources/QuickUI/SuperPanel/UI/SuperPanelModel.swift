// SuperPanelModel.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Observation

/// 超级面板的双态
public enum SuperPanelTab: String, CaseIterable, Identifiable, Sendable {
    case context = "上下文"
    case dock = "工作台"

    public var id: Self { self }

    public var icon: String {
        switch self {
        case .context: "sparkles"
        case .dock: "square.grid.2x2"
        }
    }
}

/// 超级面板的状态容器
///
/// 与 `SuperPanelController` 分开：协调器持有窗口，视图观察本对象 —— 窗口类被 SwiftUI
/// 观察会和 AttributeGraph 打架（见 `PaletteCoordinator` 的说明），纯状态对象则安全。
@MainActor
@Observable
public final class SuperPanelModel {

    /// 触发时抓到的选区 / 剪贴板文本
    public var sourceText = ""
    /// 智能预览结果
    public var previews: [SmartPreview] = []
    /// 上下文动作
    public var actions: [SuperPanelAction] = []
    /// 当前标签
    public var activeTab: SuperPanelTab = .dock
    /// 最近使用
    public var recentItems: [SuperPanelRecentItem] = []
    /// 最近一条剪贴板
    public var latestClipboard = ""
    /// 工作台工具
    public var quickTools: [SuperPanelQuickTool] = []
    /// 工作台是否展示「最近使用」
    public var showRecents = true
    /// 工作台是否展示剪贴板预览
    public var showClipboard = true
    /// 外观
    public var appearance = SuperPanelAppearance(
        opacity: SuperPanelPreferences.defaultOpacity,
        material: SuperPanelPreferences.defaultMaterial
    )
    /// 当前选中的动作下标
    public var selectedIndex = 0
    /// 顶部短暂反馈
    public var toast: String?
    /// 是否正在加载上下文
    public var isLoading = false

    public init() {}

    /// 是否处于上下文态（有选区或至少一条有意义的预览）
    public var hasContext: Bool {
        if !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return previews.contains { $0.isMeaningful }
    }

    /// 主预览（第一条有意义的）
    public var primaryPreview: SmartPreview? {
        previews.first { $0.isMeaningful }
    }

    /// 重置一次唤出时的易变状态
    public func prepareForPresentation() {
        selectedIndex = 0
        toast = nil
        isLoading = true
    }

    /// 应用一次加载结果：有内容进上下文，否则进工作台
    public func apply(
        sourceText: String,
        previews: [SmartPreview],
        actions: [SuperPanelAction],
        recentItems: [SuperPanelRecentItem],
        latestClipboard: String,
        quickTools: [SuperPanelQuickTool],
        showRecents: Bool,
        showClipboard: Bool,
        appearance: SuperPanelAppearance
    ) {
        self.sourceText = sourceText
        self.previews = previews
        self.actions = SuperPanelActionPlanner.plan(actions)
        self.recentItems = recentItems
        self.latestClipboard = latestClipboard
        self.quickTools = quickTools
        self.showRecents = showRecents
        self.showClipboard = showClipboard
        self.appearance = appearance
        self.selectedIndex = 0
        self.activeTab = hasContext ? .context : .dock
        self.isLoading = false
    }

    // MARK: - 工作台条目

    /// 工作台网格列数
    public static let dockColumns = 4

    /// 工作台里一个可执行条目
    public enum DockItem {
        case tool(SuperPanelQuickTool)
        case recent(SuperPanelRecentItem)
    }

    /// 实际展示的最近使用（受设置开关控制）
    public var visibleRecents: [SuperPanelRecentItem] {
        showRecents ? recentItems : []
    }

    /// 工作台条目总数：工具在前、最近使用在后，选中序号跨两段连续编号
    public var dockItemCount: Int { quickTools.count + visibleRecents.count }

    /// 工作台里 `index` 对应的条目
    public func dockItem(at index: Int) -> DockItem? {
        if quickTools.indices.contains(index) { return .tool(quickTools[index]) }
        let recents = visibleRecents
        let recentIndex = index - quickTools.count
        return recents.indices.contains(recentIndex) ? .recent(recents[recentIndex]) : nil
    }

    /// 当前标签下可被直达键选中的条目数
    public var selectableCount: Int {
        switch activeTab {
        case .context: actions.count
        case .dock: dockItemCount
        }
    }

    /// 直达键对应的条目序号
    public func itemIndex(forKey character: Character) -> Int? {
        SuperPanelKeys.index(forKey: character, count: selectableCount)
    }

    // MARK: - 键盘

    /// 切换标签（Tab / 上下文态的左右键）
    public func toggleTab() {
        guard hasContext else { return }
        select(activeTab == .context ? .dock : .context)
    }

    /// 选中某个标签
    public func select(_ tab: SuperPanelTab) {
        guard activeTab != tab else { return }
        activeTab = tab
        selectedIndex = 0
    }

    /// 上下移动选中项，返回是否消费了按键
    public func moveSelection(_ delta: Int) -> Bool {
        switch activeTab {
        case .context:
            guard !actions.isEmpty else { return false }
            selectedIndex = SuperPanelListNavigator.move(from: selectedIndex, delta: delta, count: actions.count)
            return true
        case .dock:
            guard dockItemCount > 0 else { return false }
            _ = stepDock(delta < 0 ? .up : .down)
            return true
        }
    }

    /// 左右键：上下文态切标签；工作台态在网格里移动，走到最左再按 ← 回到上下文
    public func moveHorizontal(_ delta: Int) -> Bool {
        switch activeTab {
        case .context:
            guard hasContext else { return false }
            select(.dock)
            return true
        case .dock:
            if stepDock(delta < 0 ? .left : .right) { return true }
            if delta < 0, hasContext {
                select(.context)
                return true
            }
            return dockItemCount > 0
        }
    }

    /// 在工作台里走一步；真的移动了才返回 true
    private func stepDock(_ direction: SuperPanelDockNavigator.Direction) -> Bool {
        if let next = SuperPanelDockNavigator.move(
            from: selectedIndex, direction,
            toolCount: quickTools.count, recentCount: visibleRecents.count,
            columns: Self.dockColumns)
        {
            selectedIndex = next
            return true
        }
        return false
    }
}
