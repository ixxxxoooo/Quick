// SuperPanelPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 超级面板插件
///
/// 对齐 Fasty 超级面板双态设计：
/// - **上下文**：识别剪贴板中的网址 / 色值 / 时间戳 / 路径 / Base64 等，给出即时动作
/// - **工作台**：常用工具快捷入口 + 剪贴板预览
/// - **项目**：保留 IDE 前台项目检测（Git / 构建 / 导航）
///
/// 不变量见 docs/features/superPanel.md
@MainActor
public final class SuperPanelPlugin: QuickPlugin {

    public static let id = "superPanel"
    public static let name = "超级面板"
    public static let icon = "bolt.square"
    public static let description =
        "上下文感知面板：识别剪贴板内容给出即时动作，空白时提供常用工具工作台，并支持 IDE 项目快捷操作。"
    public static let triggerWords = ["sp", "super", "超级", "超级面板"]

    private let log = QuickLog.plugin(SuperPanelPlugin.id)
    public var isEnabled: Bool = true

    let detector = ProjectDetector()
    let actionProvider = ActionProvider()

    public init() {}

    public func activate() {
        log.notice("超级面板插件已激活")
    }

    public func deactivate() {
        log.notice("超级面板插件已停用")
    }

    public func accepts(query: String) -> Bool {
        query.matchesAnyTrigger(Self.triggerWords)
    }

    public func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }
        return await searchItems(query: query)
    }

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }

        var items: [SearchableItem] = [
            SearchableItem(
                id: "superPanel.open",
                pluginID: Self.id,
                title: "打开超级面板",
                subtitle: "上下文动作 · 工作台 · 项目",
                icon: Self.icon,
                relevance: 0.9,
                action: {
                    EventBus.shared.post(NavigateEvent(pluginID: SuperPanelPlugin.id))
                }
            )
        ]

        // 剪贴板智能动作（不依赖面板打开）
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        let previews = SmartPreviewDetector.detect(clip)
        let contextActions = ContextActionBuilder.actions(previews: previews, sourceText: clip)
        for action in contextActions.prefix(6) {
            items.append(
                SearchableItem(
                    id: action.id,
                    pluginID: Self.id,
                    pluginName: "超级面板 · 上下文",
                    title: action.title,
                    subtitle: action.subtitle,
                    icon: action.icon,
                    relevance: 0.85,
                    action: action.execute
                )
            )
        }

        // 项目动作
        if let context = await detector.detect() {
            let actions = actionProvider.actions(for: context)
            let lowerQuery = query.lowercased()
            let isTrigger = Self.triggerWords.contains(lowerQuery)

            let matched: [SuperPanelAction] =
                isTrigger
                ? Array(actions.prefix(8))
                : Array(actions.filter { matchScore(query: lowerQuery, action: $0) > 0 }.prefix(8))

            for action in matched {
                items.append(
                    SearchableItem(
                        id: action.id,
                        pluginID: Self.id,
                        pluginName: "\(context.name) · \(action.category.rawValue)",
                        title: action.title,
                        subtitle: action.subtitle,
                        icon: action.icon,
                        relevance: isTrigger ? 0.75 : matchScore(query: lowerQuery, action: action),
                        action: action.execute
                    )
                )
            }
        }

        return items
    }

    public func defaultItems() async -> [SearchableItem] {
        [
            SearchableItem(
                id: "superPanel.entry",
                pluginID: Self.id,
                title: "超级面板",
                subtitle: "上下文感知 · 工作台 · 项目操作",
                icon: Self.icon,
                relevance: 0.2,
                action: {
                    EventBus.shared.post(NavigateEvent(pluginID: SuperPanelPlugin.id))
                }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(SuperPanelView(plugin: self))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(SuperPanelSettingsView())
    }

    private func matchScore(query: String, action: SuperPanelAction) -> Double {
        let title = action.title.lowercased()
        let subtitle = action.subtitle.lowercased()
        let category = action.category.rawValue.lowercased()
        if title.contains(query) { return 0.85 }
        if subtitle.contains(query) { return 0.75 }
        if category.contains(query) { return 0.65 }
        if title.localizedCaseInsensitiveContains(query) { return 0.7 }
        return 0
    }
}
