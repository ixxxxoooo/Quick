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
public final class AIPlugin: QuickPlugin, PluginViewProviding, PluginSettingsProviding {

    public static let id = "ai"
    public static let name = "AI 聚合"
    public static let icon = "sparkles"
    public static let description = "一站式直达主流大语言模型官网（DeepSeek、ChatGPT、Claude、Gemini 等），独立轻量窗口运行并保持登录态。"
    /// 只收「唤醒整个插件」的通用词
    ///
    /// **Provider 名不放这里。** 这个列表是「打开本插件」这条命令的关键字，答案是
    /// `triggerWords + [name]`；把 Provider 名塞进来，搜 `deepseek` 时这条通用入口会以
    /// 精确命中（1.0）盖过真正的 DeepSeek 条目（0.8）。Provider 名由
    /// `AIProviderRegistry.allKeywords` 承载，只喂动态搜索的闸门与打分，不走静态命令。
    public static let triggerWords = [
        "AI 聚合", "AI Portal", "ai", "AI", "chat", "AI 官网", "AI 设置"
    ]

    public var isEnabled = true

    private let log = QuickLog.plugin(AIPlugin.id)

    /// 各 Provider 的独立 WebView 窗口
    ///
    /// 由插件自己持有：插件停用时窗口跟着收掉，生命周期只有一个负责人。
    private let windowManager = AIWebViewWindowManager()

    public init() {}

    // MARK: - 关键词

    /// 触发词闸门与打分共用的触发词并集
    ///
    /// 每个 Provider 的触发词就是它自己的名称加上内置别名（`AIProvider.triggerWords`），
    /// 全部来自注册表 —— 没有用户配置项，所以这里可以是一个 `nonisolated` 常量式读取，
    /// 不必回主 actor。
    nonisolated static var searchKeywords: [String] {
        AIProviderRegistry.allKeywords
    }

    // MARK: - 搜索

    public func accepts(query: String) -> Bool {
        query.matchesAnyTriggerIncludingPrefix(Self.searchKeywords)
    }

    public nonisolated func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }

        // 闸门要认前缀：Provider 名是「用户打一半就该收窄」的东西 —— 打 `deep` 得能出
        // DeepSeek、打 `chatgp` 得能出 ChatGPT。整词规则做不到这件事（它保护的是
        // `ai` / `memo` 这类短触发词），所以这里用带长度下限的前缀变体，
        // 而下面那段模糊打分早就为此准备好了。
        guard query.matchesAnyTriggerIncludingPrefix(Self.searchKeywords) else {
            return []
        }

        var results: [SearchableItem] = []

        // 总入口。**id 与「打开本插件」这条静态命令相同**，所以它在真实搜索里会和静态
        // 那一条按 id 去重 —— 面板只显示一条「AI 聚合」，不会出现「门户 + 聚合」两条。
        // 这里仍然要放一条：闸门认的通用词（如「聊天」「ai聚合」）里，有些落不进
        // `triggerWords`，静态命令匹配不到，得靠动态这条兜住。
        results.append(
            SearchableItem(
                id: CommandID.openPlugin(Self.id),
                pluginID: Self.id,
                title: Self.name,
                subtitle: Self.description,
                icon: Self.icon,
                relevance: 0.6,
                action: {
                    EventBus.shared.post(NavigateEvent(pluginID: Self.id))
                }
            )
        )

        // 每个 Provider 独立搜索入口
        let keyword = query.removingTrigger(["ai", "AI", "chat", "聊天", "对话", "ai portal", "ai聚合"])
        let windows = windowManager

        for provider in AIProviderRegistry.all {
            // 设置页关掉的 Provider 不进搜索结果
            guard AIWebViewWindowManager.isProviderEnabled(provider.id) else { continue }

            // 打分用这个 Provider 自己的触发词：名称与别名一视同仁
            let keywords = provider.triggerWords
            let matchScore =
                keywords.compactMap { word -> Double? in
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
