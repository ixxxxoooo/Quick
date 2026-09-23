// AIConfigTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickCore

@Suite("AI 配置")
struct AIConfigTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ai.config.test.\(UUID().uuidString)")!
    }

    @Test("Base URL 留空时用服务商默认，并去掉末尾斜杠")
    func resolvedBaseURL() {
        #expect(AIConfig(provider: .deepseek).resolvedBaseURL == "https://api.deepseek.com/v1")
        #expect(
            AIConfig(provider: .custom, baseURL: "https://my.proxy/v1/").resolvedBaseURL
                == "https://my.proxy/v1")
        #expect(
            AIConfig(provider: .openai, baseURL: "  https://x.dev/v1  ").resolvedBaseURL == "https://x.dev/v1"
        )
    }

    @Test("模型留空时用服务商默认")
    func resolvedModel() {
        #expect(AIConfig(provider: .openai).resolvedModel == "gpt-4o-mini")
        #expect(AIConfig(provider: .openai, model: "gpt-4o").resolvedModel == "gpt-4o")
    }

    @Test("isConfigured：启用 + Key 齐备 + Base URL 有效")
    func isConfigured() {
        #expect(!AIConfig(enabled: false, provider: .deepseek, apiKey: "sk-x").isConfigured)
        #expect(!AIConfig(enabled: true, provider: .deepseek, apiKey: "").isConfigured)
        #expect(AIConfig(enabled: true, provider: .deepseek, apiKey: "sk-x").isConfigured)
        // 本地 Ollama 不需要 Key
        #expect(AIConfig(enabled: true, provider: .ollama, apiKey: "").isConfigured)
        // 自定义服务商没填 Base URL 不可用
        #expect(!AIConfig(enabled: true, provider: .custom, apiKey: "sk-x").isConfigured)
    }

    @Test("API Key 脱敏")
    func maskedAPIKey() {
        #expect(AIConfig(apiKey: "").maskedAPIKey == "")
        #expect(AIConfig(apiKey: "short").maskedAPIKey == "****")
        #expect(AIConfig(apiKey: "sk-1234567890abcd").maskedAPIKey == "sk-1…abcd")
    }

    @Test("生成参数夹紧")
    func clamps() {
        #expect(AIConfig.clampedMaxTokens(0) == AIConfig.minMaxTokens)
        #expect(AIConfig.clampedMaxTokens(999_999) == AIConfig.maxMaxTokens)
        #expect(AIConfig.clampedTemperature(-1) == 0)
        #expect(AIConfig.clampedTemperature(5) == 2)
    }

    @Test("从偏好读出配置")
    func loadsFromDefaults() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: SettingsKey.AI.enabled)
        defaults.set("anthropic", forKey: SettingsKey.AI.provider)
        defaults.set("sk-test", forKey: SettingsKey.AI.apiKey)
        defaults.set("claude-3-5-haiku-latest", forKey: SettingsKey.AI.model)
        defaults.set(1024, forKey: SettingsKey.AI.maxTokens)
        defaults.set(0.3, forKey: SettingsKey.AI.temperature)

        let config = AIConfig.load(from: defaults)
        #expect(config.enabled)
        #expect(config.provider == .anthropic)
        #expect(config.apiKey == "sk-test")
        #expect(config.resolvedModel == "claude-3-5-haiku-latest")
        #expect(config.maxTokens == 1024)
        #expect(abs(config.temperature - 0.3) < 0.0001)
    }

    @Test("没设置过时用默认：未启用、DeepSeek")
    func defaultsWhenUnset() {
        let config = AIConfig.load(from: makeDefaults())
        #expect(!config.enabled)
        #expect(config.provider == .deepseek)
        #expect(config.maxTokens == AIConfig.defaultMaxTokens)
        #expect(abs(config.temperature - AIConfig.defaultTemperature) < 0.0001)
    }
}
