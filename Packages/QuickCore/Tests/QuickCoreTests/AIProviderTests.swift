// AIProviderTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickCore

private func makeDefaults() -> UserDefaults {
    let suite = "AIProviderTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Suite("AI 预设与服务商")
struct AIProviderTests {

    @Test("预设 id 唯一，且都有可用的 Base URL")
    func presetsAreWellFormed() {
        let ids = AIProviderPresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for preset in AIProviderPresets.all {
            #expect(URL(string: preset.baseURL)?.scheme != nil, "\(preset.id) 的 Base URL 无效")
            #expect(!preset.name.isEmpty)
        }
        #expect(AIProviderPresets.preset(id: "deepseek")?.name == "DeepSeek")
        #expect(AIProviderPresets.preset(id: "openai") != nil)
    }

    @Test("本地预设不需要 Key，云端预设需要")
    func keyRequirement() {
        #expect(AIProviderPresets.preset(id: "ollama")?.requiresAPIKey == false)
        #expect(AIProviderPresets.preset(id: "deepseek")?.requiresAPIKey == true)
    }

    @Test("Anthropic 预设走 Anthropic 协议，其余走 OpenAI 兼容")
    func protocols() {
        #expect(AIProviderPresets.preset(id: "anthropic")?.apiProtocol == .anthropic)
        let others = AIProviderPresets.all.filter { $0.id != "anthropic" }
        #expect(others.allSatisfy { $0.apiProtocol == .openAICompatible })
    }

    @Test("由预设创建：只预添加第一个模型，id 各不相同")
    func createFromPreset() throws {
        let preset = try #require(AIProviderPresets.preset(id: "deepseek"))
        let first = AIProvider(preset: preset)
        let second = AIProvider(preset: preset)
        #expect(first.models == ["deepseek-chat"])
        #expect(first.id != second.id)
        #expect(first.presetID == "deepseek")
        #expect(first.baseURL == preset.baseURL)
    }

    @Test("预设没有建议模型时模型列表为空")
    func presetWithoutModels() throws {
        let preset = try #require(AIProviderPresets.preset(id: "doubao"))
        #expect(AIProvider(preset: preset).models.isEmpty)
    }

    @Test("Base URL 去首尾空白与末尾斜杠")
    func resolvedBaseURL() {
        #expect(AIProvider(name: "x", baseURL: " https://a.dev/v1/ ").resolvedBaseURL == "https://a.dev/v1")
        #expect(AIProvider(name: "x", baseURL: "https://a.dev/v1").resolvedBaseURL == "https://a.dev/v1")
        #expect(AIProvider(name: "x", baseURL: "").resolvedBaseURL == "")
    }

    @Test("添加模型：去空白、去重、拒绝空串")
    func addModel() {
        var provider = AIProvider(name: "x", baseURL: "https://a.dev")
        let added = provider.addModel("  gpt-4o  ")
        let duplicate = provider.addModel("gpt-4o")
        let blank = provider.addModel("   ")
        #expect(added)
        #expect(!duplicate)
        #expect(!blank)
        #expect(provider.models == ["gpt-4o"])
        provider.removeModel("gpt-4o")
        #expect(provider.models.isEmpty)
    }

    @Test("可用性：启用 + 有模型 + 有地址 + 需要 Key 时有 Key")
    func usability() {
        var provider = AIProvider(name: "x", baseURL: "https://a.dev", models: ["m"])
        #expect(!provider.isUsable(hasAPIKey: false))
        #expect(provider.isUsable(hasAPIKey: true))

        provider.requiresAPIKey = false
        #expect(provider.isUsable(hasAPIKey: false))

        provider.isEnabled = false
        #expect(!provider.isUsable(hasAPIKey: true))

        provider.isEnabled = true
        provider.models = []
        #expect(!provider.isUsable(hasAPIKey: true))

        provider.models = ["m"]
        provider.baseURL = "  "
        #expect(!provider.isUsable(hasAPIKey: true))
    }

    @Test("显示名：空名字回落到预设名，再回落到占位")
    func displayName() throws {
        let preset = try #require(AIProviderPresets.preset(id: "openai"))
        var provider = AIProvider(preset: preset)
        provider.name = "  "
        #expect(provider.displayName == "OpenAI")
        provider.presetID = nil
        #expect(provider.displayName == "未命名服务商")
        provider.name = "我的网关"
        #expect(provider.displayName == "我的网关")
    }

    @Test("端点会 trim Key")
    func endpoint() {
        let provider = AIProvider(name: "x", baseURL: "https://a.dev/v1/", models: ["m"])
        let endpoint = provider.endpoint(model: "m", apiKey: "  sk-1\n")
        #expect(endpoint.apiKey == "sk-1")
        #expect(endpoint.baseURL == "https://a.dev/v1")
        #expect(endpoint.model == "m")
    }

    @Test("Key 的 Keychain 账号按服务商 id 隔离")
    func keyAccountIsPerProvider() {
        let first = AIProvider(name: "a", baseURL: "x")
        let second = AIProvider(name: "b", baseURL: "x")
        #expect(first.apiKeyAccount != second.apiKeyAccount)
        #expect(first.apiKeyAccount == "ai.apiKey.\(first.id)")
    }

    @Test("Codable 往返不丢字段")
    func codableRoundTrip() throws {
        let provider = AIProvider(
            presetID: "x", name: "n", apiProtocol: .anthropic, baseURL: "https://a.dev",
            requiresAPIKey: false, models: ["a", "b"], isEnabled: false)
        let data = try JSONEncoder().encode(provider)
        #expect(try JSONDecoder().decode(AIProvider.self, from: data) == provider)
    }
}

@Suite("AIProviderStore")
struct AIProviderStoreTests {

    @Test("列表读写往返；没存过返回空")
    func providersRoundTrip() {
        let defaults = makeDefaults()
        #expect(AIProviderStore.loadProviders(from: defaults).isEmpty)

        let providers = [
            AIProvider(name: "a", baseURL: "https://a.dev", models: ["m1"]),
            AIProvider(name: "b", baseURL: "https://b.dev", models: ["m2", "m3"])
        ]
        AIProviderStore.saveProviders(providers, to: defaults)
        #expect(AIProviderStore.loadProviders(from: defaults) == providers)
    }

    @Test("存储内容损坏时回落为空，而不是崩溃")
    func corruptedStorage() {
        let defaults = makeDefaults()
        defaults.set("{not json", forKey: SettingsKey.AI.providers)
        #expect(AIProviderStore.loadProviders(from: defaults).isEmpty)
    }

    @Test("Key 存取：写入、覆盖、空串删除；不同服务商互不影响")
    func apiKeys() throws {
        let secrets = InMemorySecretStore()
        let first = AIProvider(name: "a", baseURL: "x")
        let second = AIProvider(name: "b", baseURL: "x")

        try AIProviderStore.setAPIKey("  sk-1 ", for: first, secrets: secrets)
        try AIProviderStore.setAPIKey("sk-2", for: second, secrets: secrets)
        #expect(AIProviderStore.apiKey(for: first, secrets: secrets) == "sk-1")
        #expect(AIProviderStore.apiKey(for: second, secrets: secrets) == "sk-2")

        try AIProviderStore.setAPIKey("", for: first, secrets: secrets)
        #expect(AIProviderStore.apiKey(for: first, secrets: secrets) == "")
        #expect(AIProviderStore.apiKey(for: second, secrets: secrets) == "sk-2")

        AIProviderStore.deleteAPIKey(for: second, secrets: secrets)
        #expect(AIProviderStore.apiKey(for: second, secrets: secrets) == "")
    }

    @Test("可选模型只含真正可用的服务商")
    func choicesFilterUnusable() {
        let ready = AIProvider(name: "就绪", baseURL: "https://a.dev", models: ["m1", "m2"])
        let noKey = AIProvider(name: "没 Key", baseURL: "https://b.dev", models: ["m3"])
        var disabled = AIProvider(name: "停用", baseURL: "https://c.dev", models: ["m4"])
        disabled.isEnabled = false
        let local = AIProvider(
            name: "本地", baseURL: "http://localhost:11434/v1", requiresAPIKey: false, models: ["llama"])
        let empty = AIProvider(name: "没模型", baseURL: "https://d.dev")

        let choices = AIProviderStore.choices(
            providers: [ready, noKey, disabled, local, empty]
        ) { $0.id == ready.id }

        #expect(choices.map(\.model) == ["m1", "m2", "llama"])
        #expect(choices.first?.label == "就绪 · m1")
    }

    @Test("默认模型读写往返；清除后为 nil")
    func defaultModelRoundTrip() {
        let defaults = makeDefaults()
        #expect(AIProviderStore.defaultModel(from: defaults) == nil)
        let ref = AIModelRef(providerID: "p", model: "m")
        AIProviderStore.setDefaultModel(ref, in: defaults)
        #expect(AIProviderStore.defaultModel(from: defaults) == ref)
        AIProviderStore.setDefaultModel(nil, in: defaults)
        #expect(AIProviderStore.defaultModel(from: defaults) == nil)
    }

    @Test("模型解析：优先会话模型，失效退默认，再失效退第一个，都没有为 nil")
    func resolveFallbackChain() {
        let a = AIModelChoice(ref: AIModelRef(providerID: "p1", model: "a"), providerName: "P1")
        let b = AIModelChoice(ref: AIModelRef(providerID: "p2", model: "b"), providerName: "P2")
        let gone = AIModelRef(providerID: "p9", model: "x")

        #expect(AIProviderStore.resolve(preferred: b.ref, default: a.ref, choices: [a, b]) == b)
        #expect(AIProviderStore.resolve(preferred: gone, default: b.ref, choices: [a, b]) == b)
        #expect(AIProviderStore.resolve(preferred: gone, default: gone, choices: [a, b]) == a)
        #expect(AIProviderStore.resolve(preferred: nil, default: nil, choices: []) == nil)
    }
}

@Suite("AI 生成参数")
struct AIConfigTests {

    @Test("越界值夹回合法范围")
    func clamping() {
        #expect(AIConfig.clampedMaxTokens(0) == AIConfig.minMaxTokens)
        #expect(AIConfig.clampedMaxTokens(999_999) == AIConfig.maxMaxTokens)
        #expect(AIConfig.clampedTemperature(-1) == 0)
        #expect(AIConfig.clampedTemperature(5) == AIConfig.maxTemperature)
    }

    @Test("没设置过用默认；设置过的越界值被夹住")
    func load() {
        let defaults = makeDefaults()
        #expect(AIConfig.load(from: defaults) == AIConfig())

        defaults.set(1, forKey: SettingsKey.AI.maxTokens)
        defaults.set(9.0, forKey: SettingsKey.AI.temperature)
        let config = AIConfig.load(from: defaults)
        #expect(config.maxTokens == AIConfig.minMaxTokens)
        #expect(config.temperature == AIConfig.maxTemperature)
    }
}
