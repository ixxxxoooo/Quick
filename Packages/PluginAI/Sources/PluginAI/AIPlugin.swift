// AIPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// AI 聚合门户插件
///
/// 参考 Fasty ai-portal 设计：
/// 集成 DeepSeek、ChatGPT、Gemini、Claude、豆包、Kimi、智谱、通义千问等 AI 官网，
/// 每个 Provider 在独立 WebView 窗口中运行，保持登录态。
/// 搜索直达：输入 Provider 名称（如 "deepseek"）直接打开对应窗口。
@MainActor
public final class AIPlugin: QuickPlugin {

    public static let id = "ai"
    public static let name = "AI 聚合"
    public static let icon = "sparkles"
    public static let description = "一站式直达主流大语言模型官网（DeepSeek、ChatGPT、Claude、Gemini 等），独立轻量窗口运行并保持登录态。"
    public static let triggerWords = [
        "AI 聚合", "AI Portal", "ai", "AI", "chat",
        "deepseek", "DeepSeek", "ds",
        "chatgpt", "ChatGPT", "gpt", "openai",
        "gemini", "Gemini",
        "claude", "Claude", "anthropic",
        "豆包", "doubao", "kimi", "moonshot",
        "glm", "GLM", "智谱",
        "AI 官网", "AI 设置"
    ]

    public var isEnabled = true

    private let log = QuickLog.plugin(AIPlugin.id)

    /// 各 Provider 的独立 WebView 窗口
    ///
    /// 由插件自己持有：插件停用时窗口跟着收掉，生命周期只有一个负责人。
    private let windowManager = AIWebViewWindowManager()

    public init() {}

    // MARK: - 搜索

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "ai.portal",
                pluginID: id,
                pluginName: name,
                title: "AI 聚合门户",
                subtitle: "管理所有 AI 官网窗口",
                keywords: triggerWords,
                icon: icon
            )
        ]
    }

    public func perform(commandID: String) {
        guard commandID == "ai.portal" || commandID == CommandID.openPlugin(Self.id) else { return }
        EventBus.shared.post(NavigateEvent(pluginID: Self.id))
    }

    public func accepts(query: String) -> Bool {
        query.matchesAnyTriggerIncludingPrefix(AIProviderRegistry.allKeywords)
    }

    public func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }
        return await searchItems(query: query)
    }

    public func searchItems(query: String) async -> [SearchableItem] {
        // 闸门要认前缀：Provider 名是「用户打一半就该收窄」的东西 —— 打 `deep` 得能出
        // DeepSeek、打 `chatgp` 得能出 ChatGPT。整词规则做不到这件事（它保护的是
        // `ai` / `memo` 这类短触发词），所以这里用带长度下限的前缀变体，
        // 而下面那段模糊打分早就为此准备好了。
        guard query.matchesAnyTriggerIncludingPrefix(AIProviderRegistry.allKeywords) else {
            return []
        }

        var results: [SearchableItem] = []

        // 「AI 聚合」总入口
        results.append(
            SearchableItem(
                id: "ai.portal",
                pluginID: Self.id,
                title: "AI 聚合门户",
                subtitle: "管理所有 AI 官网窗口",
                icon: "sparkles",
                relevance: 0.6,
                action: {
                    EventBus.shared.post(NavigateEvent(pluginID: "ai"))
                }
            )
        )

        // 每个 Provider 独立搜索入口
        let keyword = query.removingTrigger(["ai", "AI", "chat", "聊天", "对话", "ai portal", "ai聚合"])
        let windows = windowManager

        for provider in AIProviderRegistry.all {
            // 设置页关掉的 Provider 不进搜索结果
            guard AIWebViewWindowManager.isProviderEnabled(provider.id) else { continue }

            let matchScore =
                provider.keywords.compactMap { word -> Double? in
                    let score = word.fuzzyScore(keyword)
                    return score > 0 ? score : nil
                }.max() ?? 0

            // 如果用户只输入了 "ai"，列出所有 Provider
            let relevance = keyword.isEmpty ? 0.5 : matchScore * 0.8
            guard keyword.isEmpty || matchScore > 0 else { continue }

            results.append(
                SearchableItem(
                    id: "ai.\(provider.id)",
                    pluginID: Self.id,
                    title: provider.name,
                    subtitle: provider.description,
                    icon: provider.icon,
                    relevance: relevance,
                    action: {
                        windows.openOrFocus(providerId: provider.id)
                    }
                )
            )
        }

        return results
    }

    // MARK: - 视图

    public func makeView() -> AnyView {
        AnyView(AIPortalView(manager: windowManager))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(AISettingsView())
    }

    // MARK: - 生命周期

    public func activate() {
        log.notice("AI 聚合插件已激活，内置 \(AIProviderRegistry.all.count, privacy: .public) 个 Provider")
    }

    public func deactivate() {
        // 窗口是插件的一部分：停用就把它们收掉，不留在屏幕上没人管
        windowManager.closeAll()
        log.notice("AI 聚合插件已停用")
    }
}
