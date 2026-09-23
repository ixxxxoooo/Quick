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
        self.actions = actions
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

    /// 切换标签（左右方向键）
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
        guard activeTab == .context, !actions.isEmpty else { return false }
        let next = min(max(0, selectedIndex + delta), actions.count - 1)
        guard next != selectedIndex else { return true }
        selectedIndex = next
        return true
    }
}
