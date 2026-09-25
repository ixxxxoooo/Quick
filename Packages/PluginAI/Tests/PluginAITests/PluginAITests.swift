// PluginAITests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginAI

@Suite("AI Provider 注册表")
struct AIProviderRegistryTests {

    /// 注册表是设置页与搜索结果的唯一数据源，id 重复会让窗口互相覆盖、设置串台
    @Test("id 全局唯一")
    func idsAreUnique() {
        let ids = AIProviderRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// 顺序即展示顺序，钉住数量是为了让增删 Provider 时被迫改测试
    @Test("内置 8 个 Provider，顺序固定")
    func builtInOrder() {
        #expect(AIProviderRegistry.all.count == 8)
        #expect(
            AIProviderRegistry.all.map(\.id) == [
                "deepseek", "chatgpt", "gemini", "claude",
                "doubao", "kimi", "glm", "tongyi"
            ])
    }

    /// 每一条都要能直接丢给 WKWebView；这里只做静态校验，不发起任何请求
    @Test("URL 全部是合法的 https 地址")
    func urlsAreValid() {
        for provider in AIProviderRegistry.all {
            let url = URL(string: provider.url)
            #expect(url != nil, "\(provider.id) 的 URL 无法解析")
            #expect(url?.scheme == "https", "\(provider.id) 的 URL 不是 https")
            #expect(url?.host?.isEmpty == false, "\(provider.id) 的 URL 没有 host")
        }
    }

    /// 缺了任一字段，搜索结果或设置页就会出现空行/空图标
    @Test("每个 Provider 的名称、图标、别名、主色、描述都非空")
    func fieldsAreNonEmpty() {
        for provider in AIProviderRegistry.all {
            #expect(!provider.name.isEmpty, "\(provider.id) 缺少名称")
            #expect(!provider.icon.isEmpty, "\(provider.id) 缺少图标")
            #expect(!provider.aliases.isEmpty, "\(provider.id) 缺少别名")
            #expect(!provider.accent.isEmpty, "\(provider.id) 缺少主色")
            #expect(!provider.description.isEmpty, "\(provider.id) 缺少描述")
        }
    }

    /// 触发词是搜索直达的入口，空串会让 fuzzyScore 对任何输入都返回 0（永远搜不到）
    @Test("触发词没有空串，且都小写存储（比较时统一转小写）")
    func keywordsAreWellFormed() {
        for provider in AIProviderRegistry.all {
            for keyword in provider.triggerWords {
                #expect(!keyword.isEmpty, "\(provider.id) 有空触发词")
                #expect(keyword == keyword.lowercased(), "\(provider.id) 的触发词 \(keyword) 未小写")
            }
        }
    }

    /// 名称是结构上保证的触发词，而且必须排在首位，否则用户按服务名搜索时
    /// 会被别名抢在前面 —— 「触发词就是各自的名称」这条承诺就落空了
    @Test("每个 Provider 的名称都是第一个触发词，且触发词不重复")
    func nameIsLeadingTriggerWord() {
        for provider in AIProviderRegistry.all {
            #expect(
                provider.triggerWords.first == provider.name.lowercased(),
                "\(provider.id) 的首个触发词应当是名称")
            #expect(
                Set(provider.triggerWords).count == provider.triggerWords.count,
                "\(provider.id) 的触发词里有重复（名称与别名撞了）")
        }
    }

    /// 抽几条钉住具体值，防止「顺手改个 URL / 配色」没人发现
    @Test("具体条目与硬编码值一致")
    func knownEntries() {
        let deepseek = AIProviderRegistry.provider(for: "deepseek")
        #expect(deepseek?.name == "DeepSeek")
        #expect(deepseek?.url == "https://chat.deepseek.com")
        #expect(deepseek?.icon == "brain.head.profile")
        #expect(deepseek?.accent == "#4D6BFE")
        #expect(deepseek?.aliases == ["ds", "深度求索"])

        let doubao = AIProviderRegistry.provider(for: "doubao")
        #expect(doubao?.name == "豆包")
        #expect(doubao?.url == "https://www.doubao.com/chat/")
        #expect(doubao?.aliases == ["doubao", "字节"])

        let tongyi = AIProviderRegistry.provider(for: "tongyi")
        #expect(tongyi?.name == "通义千问")
        #expect(tongyi?.aliases == ["通义", "千问", "tongyi", "qwen", "阿里"])
    }

    @Test("按 id 查找：命中返回对应项，未命中返回 nil")
    func lookup() {
        #expect(AIProviderRegistry.provider(for: "glm")?.name == "智谱清言")
        #expect(AIProviderRegistry.provider(for: "gemini")?.name == "Gemini")
        #expect(AIProviderRegistry.provider(for: "不存在") == nil)
        #expect(AIProviderRegistry.provider(for: "") == nil)
    }

    /// 搜索闸门用的是并集：30 个 Provider 触发词（名称 + 别名）+ 7 个通用词
    @Test("allKeywords 是 Provider 触发词并集加通用词")
    func allKeywordsUnion() {
        let providerKeywords = AIProviderRegistry.all.flatMap(\.triggerWords)
        let union = AIProviderRegistry.allKeywords

        #expect(union.count == providerKeywords.count + 7)
        #expect(union.count == 37)

        for keyword in providerKeywords {
            #expect(union.contains(keyword), "并集缺少 \(keyword)")
        }
        for generic in ["ai", "AI", "聊天", "对话", "chat", "ai portal", "ai聚合"] {
            #expect(union.contains(generic), "并集缺少通用词 \(generic)")
        }
    }
}

@MainActor
@Suite("AI 聚合插件契约")
struct AIPluginTests {

    @Test("元数据符合插件约定")
    func metadata() {
        #expect(AIPlugin.id == "ai")
        #expect(AIPlugin.id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
        #expect(AIPlugin.name == "AI 聚合")
        #expect(AIPlugin.icon == "sparkles")
        #expect(!AIPlugin.triggerWords.isEmpty)
    }

    /// 只输入触发词本身时 keyword 被剥成空串，应当列出全部 Provider 而不是过滤掉
    @Test("只输入 ai 时返回门户入口 + 全部 8 个 Provider")
    func bareTriggerListsAllProviders() async {
        let plugin = AIPlugin()
        let items = await plugin.dynamicSearch(query: "ai")

        #expect(items.count == 9)
        #expect(
            items.map(\.id) == ["plugin.open.ai"] + AIProviderRegistry.all.map { "ai.\($0.id)" })
        // 门户入口排在最前，且相关度固定 0.6；其余一律 0.5
        #expect(items.first?.relevance == 0.6)
        #expect(items.dropFirst().allSatisfy { $0.relevance == 0.5 })
        #expect(items.allSatisfy { $0.pluginID == AIPlugin.id })
    }

    /// 代码不排序，只按「门户在前 + 注册表顺序」追加 —— 相关度更高的 Provider
    /// 排在相关度更低的门户之后，这正是当前的行为
    @Test("Provider 名称查询：门户在前，命中的 Provider 紧随其后")
    func providerQuery() async {
        let plugin = AIPlugin()
        let items = await plugin.dynamicSearch(query: "deepseek")

        #expect(items.map(\.id) == ["plugin.open.ai", "ai.deepseek"])
        #expect(items.map(\.relevance) == [0.6, 0.8])

        let provider = AIProviderRegistry.provider(for: "deepseek")
        #expect(items[1].title == provider?.name)
        #expect(items[1].subtitle == provider?.description)
        #expect(items[1].icon == provider?.icon)
    }

    /// 关键词包含匹配（fuzzyScore == 0.7）也要能搜到，且相关度按 0.8 折算
    @Test("部分关键词（gpt）只命中 ChatGPT")
    func partialKeywordQuery() async {
        let plugin = AIPlugin()
        let items = await plugin.dynamicSearch(query: "gpt")

        #expect(items.map(\.id) == ["plugin.open.ai", "ai.chatgpt"])
        #expect(items.map(\.relevance) == [0.6, 0.8])
    }

    /// 中文关键词同样直达
    @Test("中文关键词（通义）只命中通义千问")
    func chineseKeywordQuery() async {
        let plugin = AIPlugin()
        let items = await plugin.dynamicSearch(query: "通义")

        #expect(items.map(\.id) == ["plugin.open.ai", "ai.tongyi"])
        #expect(items[1].title == "通义千问")
    }

    /// 触发词就是各自的名称，所以**打全名必须直达** —— 别名表里只有 `智谱` / `通义`
    /// 这类片段（拉丁别名按整词比、中文别名按前缀比），全名反而一条都命不中。
    ///
    /// 用例刻意避开 `deepseek`：设置页那组用例会临时把它停用，两个 suite 并发跑时
    /// 搜它就只能是时灵时不灵。
    @Test("搜完整服务名直达对应 Provider")
    func fullNameQueryFindsProvider() async throws {
        let cases = [
            ("智谱清言", "glm"), ("通义千问", "tongyi"),
            ("chatgpt", "chatgpt"), ("ChatGPT", "chatgpt"),
            ("豆包", "doubao"), ("kimi", "kimi")
        ]

        for (query, id) in cases {
            let items = await AIPlugin().dynamicSearch(query: query)
            try #require(
                items.map(\.id) == ["plugin.open.ai", "ai.\(id)"],
                "搜「\(query)」应当直达 \(id)")
            #expect(items[1].relevance == 0.8, "整名命中与别名同权")
        }
    }

    /// 触发词闸门按整词匹配：`clipboard` 里的 `ai` 不该放行 ——
    /// 否则打 `clipboard` 时会冒出一整屏 AI 入口
    @Test("未命中触发词时不返回任何结果")
    func unrelatedQueryReturnsNothing() async {
        let plugin = AIPlugin()
        #expect(await plugin.dynamicSearch(query: "clipboard").isEmpty)
        #expect(await plugin.dynamicSearch(query: "天气").isEmpty)
        #expect(await plugin.dynamicSearch(query: "").isEmpty)
    }

    // MARK: - 前缀查询

    /// 回归测试：闸门原来只认整词，`deep` 进不来，下面那段模糊打分再准也没机会跑
    @Test("打一半也能找到 Provider")
    func prefixQueryFindsProvider() async {
        let plugin = AIPlugin()

        let deep = await plugin.dynamicSearch(query: "deep")
        #expect(deep.map(\.id) == ["plugin.open.ai", "ai.deepseek"])
        #expect(deep[1].relevance == 0.9 * 0.8, "前缀命中按 0.9 折算")

        #expect(
            await plugin.dynamicSearch(query: "chatgp").map(\.id) == ["plugin.open.ai", "ai.chatgpt"])
    }

    /// 前缀是「以触发词开头」：`seek` 是 deepseek 的中间片段，不该放行
    @Test("中间片段不算前缀")
    func infixQueryReturnsNothing() async {
        let plugin = AIPlugin()
        #expect(await plugin.dynamicSearch(query: "seek").isEmpty)
    }

    /// 闸门有长度下限：一两个字母会把 `ai` / `gpt` 这类短触发词变成噪音源
    @Test("太短的前缀不放行")
    func tooShortPrefixReturnsNothing() async {
        let plugin = AIPlugin()
        #expect(await plugin.dynamicSearch(query: "de").isEmpty)
        #expect(await plugin.dynamicSearch(query: "d").isEmpty)
    }

    /// 命中的 Provider 必须能被窗口管理器认出来：id 就是注册表里的 id
    @Test("返回项的 pluginID 一律是插件 id")
    func pluginIDStamped() async {
        let plugin = AIPlugin()
        for query in ["ai", "kimi", "glm", "豆包"] {
            let items = await plugin.dynamicSearch(query: query)
            #expect(!items.isEmpty, "\(query) 应当有结果")
            #expect(items.allSatisfy { $0.pluginID == AIPlugin.id })
        }
    }
}
