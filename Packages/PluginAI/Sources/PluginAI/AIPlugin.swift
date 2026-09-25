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
        "AI 聚合", "ai", "chat"
    ]

    public var isEnabled = true

    private let log = QuickLog.plugin(AIPlugin.id)

    /// 各 Provider 的独立 WebView 窗口
    ///
    /// 由插件自己持有：插件停用时窗口跟着收掉，生命周期只有一个负责人。
    private let windowManager = AIWebViewWindowManager()

    public init() {}

    // MARK: - 命令

    /// 聚合窗口命令的 id：`ai.mergedWindow`
    public nonisolated static let mergedWindowCommandID = "\(id).mergedWindow"

    /// 每个启用的 Provider 一条命令，加上直接打开聚合窗口的命令
    ///
    /// 它存在的理由**不是搜索**（搜索结果由 `dynamicSearch` 现算，能跟着开关实时变），
    /// 而是**快捷键**：快捷键页把用户写的关键字解到具体一条命令，`KeywordResolver`
    /// 只认命令声明，动态结果不在候选里 —— 不声明成命令，「⌥D + deepseek」就解不出来。
    ///
    /// 命令 id 与动态条目共用 `providerCommandID(_:)`，两条路撞在同一个 id 上，
    /// 聚合搜索按 id 去重后只留一条，不会出现两行同名的 DeepSeek。
    ///
    /// 停用的 Provider 不进命令表：留一条解得出关键字、按下去却什么都不做的命令，
    /// 就是「看起来能用」的假象。开关一变，设置页会发 `CommandCatalogChangedEvent`
    /// 让宿主重建快照。
    public nonisolated static var functionCommands: [CommandDescriptor] {
        let mergedWindowCommand = CommandDescriptor(
            id: mergedWindowCommandID,
            pluginID: id,
            pluginName: name,
            title: "AI 聚合窗口",
            subtitle: "打开多标签 AI 聚合窗口，保持上次标签页状态",
            keywords: ["ai 聚合窗口", "ai聚合窗口", "聚合窗口", "ai窗口", "ai window"],
            icon: "macwindow.on.rectangle"
        )
        let providerCommands = AIProviderRegistry.all
            .filter { AIWebViewWindowManager.isProviderEnabled($0.id) }
            .map { provider in
                CommandDescriptor(
                    id: providerCommandID(provider.id),
                    pluginID: id,
                    pluginName: name,
                    title: provider.name,
                    subtitle: provider.description,
                    keywords: provider.triggerWords,
                    icon: provider.icon
                )
            }
        return [mergedWindowCommand] + providerCommands
    }

    /// Provider 命令的 id：`ai.<providerId>`
    ///
    /// 静态命令与动态搜索结果都用它 —— 两处各写一遍字符串，去重就会悄悄失效。
    nonisolated static func providerCommandID(_ providerID: String) -> String {
        "\(id).\(providerID)"
    }

    /// 从命令 id 反解 Provider id；不是 Provider 命令时返回 nil
    ///
    /// `public`：宿主 `invoke` 要认「这是独立窗口命令」—— 不能按「面板正显示 ai」
    /// 直接 hide，否则 ⌥D 在门户开着时只会关面板、到不了 `perform` 里的 toggle。
    public nonisolated static func providerID(fromCommandID commandID: String) -> String? {
        let prefix = "\(id)."
        guard commandID.hasPrefix(prefix) else { return nil }
        let providerID = String(commandID.dropFirst(prefix.count))
        return AIProviderRegistry.provider(for: providerID) == nil ? nil : providerID
    }

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
                    id: Self.providerCommandID(provider.id),
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

    // MARK: - 执行

    /// 执行一条命令
    ///
    /// Provider 命令走窗口切换（开着再按就关，与主面板 / `plugin.open.*` 热键同语义）；
    /// 其余（「打开本插件」等）仍然导航进插件面板。
    public func perform(commandID: String) {
        if commandID == Self.mergedWindowCommandID {
            let wasOpen = windowManager.isMergedWindowOpen()
            let nowOpen = windowManager.toggleMergedWindow()
            if !wasOpen, !nowOpen {
                log.notice("命令 \(commandID, privacy: .public) 没能打开聚合窗口")
            }
            return
        }
        guard let providerID = Self.providerID(fromCommandID: commandID) else {
            EventBus.shared.post(NavigateEvent(pluginID: Self.id))
            return
        }
        // 停用的 Provider 在命令表里已经没有条目，这里只可能撞上「刚停用、命令表还没
        // 重建」的一瞬。`toggle` 自己会拒绝。
        // 开着再按必须关掉：只调 `openOrFocus` 时窗口会一直留在前台，快捷键形同失灵。
        let wasOpen = windowManager.isWindowOpen(for: providerID)
        let nowOpen = windowManager.toggle(providerId: providerID)
        if !wasOpen, !nowOpen {
            log.notice("命令 \(commandID, privacy: .public) 没能打开窗口")
        }
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
