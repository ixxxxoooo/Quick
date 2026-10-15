// AIProviderStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 服务商列表与默认模型的读写
///
/// 无状态：每次现读 `UserDefaults` / Keychain，调用方（设置页、对话控制器、`AIService`）
/// 各自按需读取，不需要在 `AppCore` 上再挂一个所有者。
///
/// **API Key 只存 Keychain**，每个服务商一个账号（`AIProvider.apiKeyAccount`）。
public enum AIProviderStore {

    // MARK: - 服务商列表

    public static func loadProviders(from defaults: UserDefaults = .standard) -> [AIProvider] {
        guard let json = defaults.string(forKey: SettingsKey.AI.providers),
            let data = json.data(using: .utf8),
            let providers = try? JSONDecoder().decode([AIProvider].self, from: data)
        else { return [] }
        return providers
    }

    public static func saveProviders(
        _ providers: [AIProvider], to defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(providers),
            let json = String(data: data, encoding: .utf8)
        else {
            QuickLog.persistence.error("服务商列表编码失败，未保存")
            return
        }
        defaults.set(json, forKey: SettingsKey.AI.providers)
    }

    // MARK: - API Key

    public static func apiKey(
        for provider: AIProvider, secrets: any SecretStoring = KeychainStore.shared
    ) -> String {
        (try? secrets.get(provider.apiKeyAccount)) ?? ""
    }

    /// 写入（空串即删除）。失败向上抛：设置页要告诉用户「没存上」
    public static func setAPIKey(
        _ key: String, for provider: AIProvider,
        secrets: any SecretStoring = KeychainStore.shared
    ) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try secrets.delete(provider.apiKeyAccount)
        } else {
            try secrets.set(trimmed, for: provider.apiKeyAccount)
        }
    }

    /// 删除服务商时一并清掉它的 Key，避免 Keychain 里留下无主的机密
    public static func deleteAPIKey(
        for provider: AIProvider, secrets: any SecretStoring = KeychainStore.shared
    ) {
        do {
            try secrets.delete(provider.apiKeyAccount)
        } catch {
            QuickLog.persistence.error(
                "清除服务商 Key 失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 可选模型

    /// 对话里所有可选的模型：只包含「真能用」的服务商（已启用、有模型、需要 Key 时已填）
    public static func choices(
        providers: [AIProvider], hasAPIKey: (AIProvider) -> Bool
    ) -> [AIModelChoice] {
        providers.flatMap { provider -> [AIModelChoice] in
            guard provider.isUsable(hasAPIKey: hasAPIKey(provider)) else { return [] }
            return provider.models.map {
                AIModelChoice(
                    ref: AIModelRef(providerID: provider.id, model: $0),
                    providerName: provider.displayName)
            }
        }
    }

    /// 读出所有可选模型（会读 Keychain，调用方不要在 `body` 里调）
    public static func loadChoices(
        defaults: UserDefaults = .standard,
        secrets: any SecretStoring = KeychainStore.shared
    ) -> [AIModelChoice] {
        choices(providers: loadProviders(from: defaults)) { provider in
            !apiKey(for: provider, secrets: secrets).isEmpty
        }
    }

    // MARK: - 默认模型

    public static func defaultModel(from defaults: UserDefaults = .standard) -> AIModelRef? {
        guard let json = defaults.string(forKey: SettingsKey.AI.defaultModel),
            let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(AIModelRef.self, from: data)
    }

    public static func setDefaultModel(
        _ ref: AIModelRef?, in defaults: UserDefaults = .standard
    ) {
        guard let ref, let data = try? JSONEncoder().encode(ref),
            let json = String(data: data, encoding: .utf8)
        else {
            defaults.removeObject(forKey: SettingsKey.AI.defaultModel)
            return
        }
        defaults.set(json, forKey: SettingsKey.AI.defaultModel)
    }

    /// 解析出实际要用的模型：优先用 `preferred`，失效（服务商被删 / 模型被移除 / 不可用）
    /// 就退到默认模型，再退到第一个可选项
    public static func resolve(
        preferred: AIModelRef?, default defaultRef: AIModelRef?, choices: [AIModelChoice]
    ) -> AIModelChoice? {
        for candidate in [preferred, defaultRef] {
            if let candidate, let hit = choices.first(where: { $0.ref == candidate }) {
                return hit
            }
        }
        return choices.first
    }
}
