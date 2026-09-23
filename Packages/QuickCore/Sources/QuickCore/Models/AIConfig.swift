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
/// 而不是每个插件各自记一份 Key 与模型。
///
/// **API Key 只存 Keychain**，其余偏好仍在 `UserDefaults`。启动时会把旧版写在
/// `UserDefaults` 里的 Key 迁走并清掉。
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

    /// Keychain 账号名
    public static let apiKeyAccount = "ai.apiKey"

    /// 迁移完成标记（成功迁完才置位；失败保留 UserDefaults 原值以便重试）
    public static let apiKeyMigratedFlag = "quick.ai.apiKey.migratedToKeychain.v1"

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

    /// 从偏好 + Keychain 读出配置
    public static func load(
        from defaults: UserDefaults = .standard,
        secrets: any SecretStoring = KeychainStore.shared
    ) -> AIConfig {
        migrateAPIKeyIfNeeded(defaults: defaults, secrets: secrets)

        let provider =
            defaults.string(forKey: SettingsKey.AI.provider)
            .flatMap(AIProviderKind.init(rawValue:)) ?? .deepseek
        let rawMax = defaults.object(forKey: SettingsKey.AI.maxTokens) as? Int ?? defaultMaxTokens
        let rawTemp =
            defaults.object(forKey: SettingsKey.AI.temperature) as? Double
            ?? defaultTemperature
        let apiKey = (try? secrets.get(apiKeyAccount)) ?? ""
        return AIConfig(
            enabled: defaults.bool(forKey: SettingsKey.AI.enabled),
            provider: provider,
            apiKey: apiKey,
            baseURL: defaults.string(forKey: SettingsKey.AI.baseURL) ?? "",
            model: defaults.string(forKey: SettingsKey.AI.model) ?? "",
            maxTokens: clampedMaxTokens(rawMax),
            temperature: clampedTemperature(rawTemp)
        )
    }

    /// 把 API Key 写入 Keychain，并清掉 UserDefaults 里的旧值
    public static func saveAPIKey(
        _ key: String,
        defaults: UserDefaults = .standard,
        secrets: any SecretStoring = KeychainStore.shared
    ) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try secrets.delete(apiKeyAccount)
        } else {
            try secrets.set(trimmed, for: apiKeyAccount)
        }
        defaults.removeObject(forKey: SettingsKey.AI.apiKey)
        defaults.set(true, forKey: apiKeyMigratedFlag)
    }

    /// 一次性：UserDefaults 旧 Key → Keychain，成功后清掉偏好里的明文
    public static func migrateAPIKeyIfNeeded(
        defaults: UserDefaults = .standard,
        secrets: any SecretStoring = KeychainStore.shared
    ) {
        let log = QuickLog.persistence
        let legacy = defaults.string(forKey: SettingsKey.AI.apiKey) ?? ""
        let existing = (try? secrets.get(apiKeyAccount)) ?? ""

        // Keychain 已有值：只清偏好残留，并记迁移完成
        if !existing.isEmpty {
            if !legacy.isEmpty {
                defaults.removeObject(forKey: SettingsKey.AI.apiKey)
                log.notice("已清除 UserDefaults 中残留的 API Key（Keychain 优先）")
            }
            defaults.set(true, forKey: apiKeyMigratedFlag)
            return
        }

        guard !legacy.isEmpty else {
            // 两边都空：也算迁完，避免每次启动空跑
            if defaults.bool(forKey: apiKeyMigratedFlag) == false {
                defaults.set(true, forKey: apiKeyMigratedFlag)
            }
            return
        }

        do {
            try secrets.set(legacy, for: apiKeyAccount)
            defaults.removeObject(forKey: SettingsKey.AI.apiKey)
            defaults.set(true, forKey: apiKeyMigratedFlag)
            log.notice("API Key 已迁入 Keychain")
        } catch {
            log.error("API Key 迁移失败：\(error.localizedDescription, privacy: .public)")
            // 失败不置 flag，下次启动再试；UserDefaults 原值保留
        }
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
