// AIConfig.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// AI 服务商
///
/// 除 Anthropic 外都走 OpenAI 兼容协议；Anthropic 的接口形态不同，由 `AIService` 单独处理。
public enum AIProviderKind: String, CaseIterable, Sendable, Identifiable {
    case deepseek
    case openai
    case anthropic
    case ollama
    case custom

    public var id: Self { self }

    public var title: String {
        switch self {
        case .deepseek: "DeepSeek"
        case .openai: "OpenAI"
        case .anthropic: "Anthropic Claude"
        case .ollama: "Ollama（本地）"
        case .custom: "自定义（OpenAI 兼容）"
        }
    }

    /// 默认 Base URL（用户没填时用它）
    public var defaultBaseURL: String {
        switch self {
        case .deepseek: "https://api.deepseek.com/v1"
        case .openai: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .ollama: "http://localhost:11434/v1"
        case .custom: ""
        }
    }

    /// 默认模型（用户没填时用它）
    public var defaultModel: String {
        switch self {
        case .deepseek: "deepseek-chat"
        case .openai: "gpt-4o-mini"
        case .anthropic: "claude-3-5-sonnet-latest"
        case .ollama: "llama3.2"
        case .custom: ""
        }
    }

    /// 是否必须填 API Key（本地 Ollama 不需要）
    public var requiresAPIKey: Bool {
        self != .ollama
    }

    /// 常见模型候选（设置页给个下拉，也可以直接手填）
    public var suggestedModels: [String] {
        switch self {
        case .deepseek: ["deepseek-chat", "deepseek-reasoner"]
        case .openai: ["gpt-4o-mini", "gpt-4o", "o3-mini"]
        case .anthropic: ["claude-3-5-sonnet-latest", "claude-3-5-haiku-latest"]
        case .ollama: ["llama3.2", "qwen2.5", "deepseek-r1"]
        case .custom: []
        }
    }
}

/// 宿主级 AI 配置
///
/// 一份配置、所有插件共用：翻译、摘要、改写这类能力都通过 `AIService` 读它，
/// 而不是每个插件各自记一份 Key 与模型。存 `UserDefaults`（它是用户可改、可重置的偏好）。
public struct AIConfig: Sendable, Equatable {

    public var enabled: Bool
    public var provider: AIProviderKind
    public var apiKey: String
    /// 自定义 Base URL；空串表示用服务商默认
    public var baseURL: String
    /// 模型名；空串表示用服务商默认
    public var model: String
    public var maxTokens: Int
    public var temperature: Double

    public static let defaultMaxTokens = 4096
    public static let minMaxTokens = 256
    public static let maxMaxTokens = 32768
    public static let defaultTemperature = 0.7

    public init(
        enabled: Bool = false,
        provider: AIProviderKind = .deepseek,
        apiKey: String = "",
        baseURL: String = "",
        model: String = "",
        maxTokens: Int = AIConfig.defaultMaxTokens,
        temperature: Double = AIConfig.defaultTemperature
    ) {
        self.enabled = enabled
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    /// 从偏好读出配置
    public static func load(from defaults: UserDefaults = .standard) -> AIConfig {
        let provider =
            defaults.string(forKey: SettingsKey.AI.provider)
            .flatMap(AIProviderKind.init(rawValue:)) ?? .deepseek
        let rawMax = defaults.object(forKey: SettingsKey.AI.maxTokens) as? Int ?? defaultMaxTokens
        let rawTemp =
            defaults.object(forKey: SettingsKey.AI.temperature) as? Double
            ?? defaultTemperature
        return AIConfig(
            enabled: defaults.bool(forKey: SettingsKey.AI.enabled),
            provider: provider,
            apiKey: defaults.string(forKey: SettingsKey.AI.apiKey) ?? "",
            baseURL: defaults.string(forKey: SettingsKey.AI.baseURL) ?? "",
            model: defaults.string(forKey: SettingsKey.AI.model) ?? "",
            maxTokens: clampedMaxTokens(rawMax),
            temperature: clampedTemperature(rawTemp)
        )
    }

    /// 实际使用的 Base URL（去掉末尾斜杠）
    public var resolvedBaseURL: String {
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = raw.isEmpty ? provider.defaultBaseURL : raw
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }

    /// 实际使用的模型
    public var resolvedModel: String {
        let raw = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? provider.defaultModel : raw
    }

    /// 配置是否可用（启用 + Key 齐备 + Base URL 有效）
    public var isConfigured: Bool {
        guard enabled, !resolvedBaseURL.isEmpty else { return false }
        if provider.requiresAPIKey && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    /// 脱敏后的 Key，给设置页显示用
    public var maskedAPIKey: String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "" }
        guard key.count > 8 else { return "****" }
        return "\(key.prefix(4))…\(key.suffix(4))"
    }

    public static func clampedMaxTokens(_ value: Int) -> Int {
        min(maxMaxTokens, max(minMaxTokens, value))
    }

    public static func clampedTemperature(_ value: Double) -> Double {
        min(2, max(0, value))
    }
}
