// AIModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// AI 聚合门户模块
///
/// 参考 Fasty ai-portal 设计：
/// 集成 DeepSeek、ChatGPT、Gemini、Claude、豆包、Kimi、智谱、通义千问等 AI 官网，
/// 每个 Provider 在独立 WebView 窗口中运行，保持登录态。
/// 搜索直达：输入 Provider 名称（如 "deepseek"）直接打开对应窗口。
@MainActor
public final class AIModule: QuickModule {

    public static let id = "ai"
    public static let name = "AI 聚合"
    public static let icon = "sparkles"
    public static let triggerWords = [
        "ai", "AI", "聊天", "对话", "chat",
        "deepseek", "chatgpt", "gpt", "openai",
        "gemini", "claude", "anthropic",
        "豆包", "doubao", "kimi", "moonshot",
        "glm", "智谱", "通义", "千问", "tongyi",
        "ai portal", "ai聚合"
    ]

    public var isEnabled = true

    private let log = QuickLog.module(AIModule.id)

    public init() {}

    // MARK: - 搜索

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(AIProviderRegistry.allKeywords) else { return [] }

        var results: [SearchableItem] = []

        // 「AI 聚合」总入口
        results.append(
            SearchableItem(
                id: "ai.portal",
                moduleID: Self.id,
                title: "AI 聚合门户",
                subtitle: "管理所有 AI 官网窗口",
                icon: "sparkles",
                relevance: 0.6,
                action: {
                    EventBus.shared.post(NavigateEvent(moduleID: "ai"))
                }
            )
        )

        // 每个 Provider 独立搜索入口
        let keyword = query.removingTrigger(["ai", "AI", "chat", "聊天", "对话", "ai portal", "ai聚合"])

        for provider in AIProviderRegistry.all {
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
                    moduleID: Self.id,
                    title: provider.name,
                    subtitle: provider.description,
                    icon: provider.icon,
                    relevance: relevance,
                    action: {
                        AIWebViewWindowManager.shared.openOrFocus(providerId: provider.id)
                    }
                )
            )
        }

        return results
    }

    // MARK: - 视图

    public func makeView() -> AnyView {
        AnyView(AIPortalView())
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(AISettingsView())
    }

    // MARK: - 生命周期

    public func activate() {
        log.notice("AI 聚合模块已激活，内置 \(AIProviderRegistry.all.count, privacy: .public) 个 Provider")
    }

    public func deactivate() {
        log.notice("AI 聚合模块已停用")
    }
}
