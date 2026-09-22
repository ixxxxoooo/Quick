// SuperPanelPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 超级面板插件
///
/// 感知当前项目上下文的命令面板。通过检测前台应用（Xcode、VS Code、
/// Terminal 等）的当前项目路径，提供针对该项目的快速操作：
/// 打开终端、运行构建、查看 Git 状态、快速访问项目文件等。
///
/// 性能策略：
/// - 项目检测：前台应用变化才重新检测，同应用返回缓存
/// - Git 分支：直接读 `.git/HEAD` 文件（微秒级），不跑 `git` 进程（毫秒级）
/// - 操作列表：按项目路径缓存，上下文不变不重算
/// - 搜索：纯内存过滤，零 IO
///
/// 不变量与内部约定见 docs/features/superPanel.md
@MainActor
public final class SuperPanelPlugin: QuickPlugin {

    // MARK: - QuickPlugin 元信息

    public static let id = "superPanel"
    public static let name = "超级面板"
    public static let icon = "bolt.square"
    public static let description = "感知当前项目上下文的命令面板，提供 Git 操作、构建命令、快速导航等项目相关快捷操作。"
    public static let triggerWords = ["sp", "super", "超级", "超级面板"]

    // MARK: - 状态

    private let log = QuickLog.plugin(SuperPanelPlugin.id)
    public var isEnabled: Bool = true

    /// 项目检测器
    let detector = ProjectDetector()

    /// 操作提供器
    let actionProvider = ActionProvider()

    // MARK: - 生命周期

    public init() {}

    public func activate() {
        log.notice("超级面板插件已激活")
    }

    public func deactivate() {
        log.notice("超级面板插件已停用")
    }

    // MARK: - 搜索

    public func accepts(query: String) -> Bool {
        query.matchesAnyTrigger(Self.triggerWords)
    }

    public func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }
        return await searchItems(query: query)
    }

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }

        // 只有触发词命中才探测前台项目，避免每次按键都扫窗口和磁盘
        guard let context = await detector.detect() else { return [] }

        let actions = actionProvider.actions(for: context)

        // 如果查询刚好是触发词，返回所有操作
        let lowerQuery = query.lowercased()
        let isTrigger = Self.triggerWords.contains(lowerQuery)

        if isTrigger {
            return actions.map { toSearchItem($0, context: context, relevance: 0.8) }
        }

        // 过滤匹配的操作
        return actions.compactMap { action in
            let score = matchScore(query: lowerQuery, action: action)
            guard score > 0 else { return nil }
            return toSearchItem(action, context: context, relevance: score)
        }
    }

    public func defaultItems() async -> [SearchableItem] {
        // 首屏展示一个入口
        [
            SearchableItem(
                id: "superPanel.entry",
                pluginID: Self.id,
                title: "超级面板",
                subtitle: "项目上下文快捷操作",
                icon: Self.icon,
                relevance: 0.2,
                action: {
                    EventBus.shared.post(NavigateEvent(pluginID: SuperPanelPlugin.id))
                }
            )
        ]
    }

    // MARK: - 视图

    public func makeView() -> AnyView {
        AnyView(SuperPanelView(plugin: self))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(SuperPanelSettingsView())
    }

    // MARK: - 内部

    /// 匹配打分
    ///
    /// 纯内存操作：只比较字符串，不做 IO。
    private func matchScore(query: String, action: SuperPanelAction) -> Double {
        let title = action.title.lowercased()
        let subtitle = action.subtitle.lowercased()
        let category = action.category.rawValue.lowercased()

        // 标题完全包含
        if title.contains(query) { return 0.85 }
        // 副标题（命令）包含
        if subtitle.contains(query) { return 0.75 }
        // 分类匹配
        if category.contains(query) { return 0.65 }

        // 拼音首字母匹配（中文场景）
        if title.localizedCaseInsensitiveContains(query) { return 0.7 }

        return 0
    }

    /// 将 SuperPanelAction 转为 SearchableItem
    private func toSearchItem(
        _ action: SuperPanelAction,
        context: ProjectContext,
        relevance: Double
    ) -> SearchableItem {
        SearchableItem(
            id: action.id,
            pluginID: Self.id,
            pluginName: "\(context.name) · \(action.category.rawValue)",
            title: action.title,
            subtitle: action.subtitle,
            icon: action.icon,
            relevance: relevance,
            action: action.execute
        )
    }
}
