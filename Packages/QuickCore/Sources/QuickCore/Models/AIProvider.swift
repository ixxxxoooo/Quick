// AIProvider.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// AI 接口协议
///
/// 市面上绝大多数服务商都提供 OpenAI 兼容接口（`/chat/completions`），
/// 只有 Anthropic 用自己的 `/messages`，鉴权头与流式事件都不同。
public enum AIAPIProtocol: String, Codable, CaseIterable, Sendable, Identifiable {
    case openAICompatible
    case anthropic

    public var id: Self { self }

    public var title: String {
        switch self {
        case .openAICompatible: "OpenAI 兼容"
        case .anthropic: "Anthropic"
        }
    }
}

/// 预设服务商：用户点一下就能添加，省掉手填 Base URL
public struct AIProviderPreset: Identifiable, Equatable, Sendable {

    public let id: String
    public let name: String
    /// SF Symbol（不选会被系统本地化成别的字形的符号）
    public let symbol: String
    public let apiProtocol: AIAPIProtocol
    public let baseURL: String
    /// 常见模型。不保证是最新的 —— 设置页提供「自动拉取」以服务商返回的为准
    public let suggestedModels: [String]
    public let requiresAPIKey: Bool
    /// 申请 API Key 的页面
    public let keyURL: String?

    public init(
        id: String,
        name: String,
        symbol: String,
        apiProtocol: AIAPIProtocol = .openAICompatible,
        baseURL: String,
        suggestedModels: [String],
        requiresAPIKey: Bool = true,
        keyURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.apiProtocol = apiProtocol
        self.baseURL = baseURL
        self.suggestedModels = suggestedModels
        self.requiresAPIKey = requiresAPIKey
        self.keyURL = keyURL
    }
}

/// 内置的常见服务商
public enum AIProviderPresets {

    public static let all: [AIProviderPreset] = [
        AIProviderPreset(
            id: "deepseek", name: "DeepSeek", symbol: "water.waves",
            baseURL: "https://api.deepseek.com/v1",
            suggestedModels: ["deepseek-chat", "deepseek-reasoner"],
            keyURL: "https://platform.deepseek.com/api_keys"),
        AIProviderPreset(
            id: "openai", name: "OpenAI", symbol: "sparkles",
            baseURL: "https://api.openai.com/v1",
            suggestedModels: ["gpt-4o-mini", "gpt-4o"],
            keyURL: "https://platform.openai.com/api-keys"),
        AIProviderPreset(
            id: "anthropic", name: "Anthropic Claude", symbol: "asterisk",
            apiProtocol: .anthropic,
            baseURL: "https://api.anthropic.com/v1",
            suggestedModels: ["claude-3-5-haiku-latest", "claude-3-5-sonnet-latest"],
            keyURL: "https://console.anthropic.com/settings/keys"),
        AIProviderPreset(
            id: "gemini", name: "Google Gemini", symbol: "diamond",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            suggestedModels: ["gemini-2.0-flash"],
            keyURL: "https://aistudio.google.com/apikey"),
        AIProviderPreset(
            id: "moonshot", name: "Moonshot Kimi", symbol: "moon.stars",
            baseURL: "https://api.moonshot.cn/v1",
            suggestedModels: ["moonshot-v1-8k"],
            keyURL: "https://platform.moonshot.cn/console/api-keys"),
        AIProviderPreset(
            id: "zhipu", name: "智谱 GLM", symbol: "brain",
            baseURL: "https://open.bigmodel.cn/api/paas/v4",
            suggestedModels: ["glm-4-flash", "glm-4-plus"],
            keyURL: "https://open.bigmodel.cn/usercenter/apikeys"),
        AIProviderPreset(
            id: "qwen", name: "通义千问", symbol: "cloud",
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            suggestedModels: ["qwen-plus", "qwen-turbo", "qwen-max"],
            keyURL: "https://bailian.console.aliyun.com/?apiKey=1"),
        AIProviderPreset(
            id: "doubao", name: "豆包（火山方舟）", symbol: "leaf",
            baseURL: "https://ark.cn-beijing.volces.com/api/v3",
            suggestedModels: [],
            keyURL: "https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey"),
        AIProviderPreset(
            id: "siliconflow", name: "硅基流动", symbol: "cpu",
            baseURL: "https://api.siliconflow.cn/v1",
            suggestedModels: ["Qwen/Qwen2.5-7B-Instruct", "deepseek-ai/DeepSeek-V3"],
            keyURL: "https://cloud.siliconflow.cn/account/ak"),
        AIProviderPreset(
            id: "openrouter", name: "OpenRouter", symbol: "point.3.connected.trianglepath.dotted",
            baseURL: "https://openrouter.ai/api/v1",
            suggestedModels: ["openai/gpt-4o-mini"],
            keyURL: "https://openrouter.ai/keys"),
        AIProviderPreset(
            id: "groq", name: "Groq", symbol: "bolt",
            baseURL: "https://api.groq.com/openai/v1",
            suggestedModels: ["llama-3.3-70b-versatile"],
            keyURL: "https://console.groq.com/keys"),
        AIProviderPreset(
            id: "ollama", name: "Ollama（本地）", symbol: "desktopcomputer",
            baseURL: "http://localhost:11434/v1",
            suggestedModels: ["llama3.2", "qwen2.5"],
            requiresAPIKey: false),
        AIProviderPreset(
            id: "lmstudio", name: "LM Studio（本地）", symbol: "externaldrive",
            baseURL: "http://localhost:1234/v1",
            suggestedModels: [],
            requiresAPIKey: false)
    ]

    public static func preset(id: String) -> AIProviderPreset? {
        all.first { $0.id == id }
    }
}

/// 一个已添加的服务商
///
/// 同一个预设可以添加多份（例如两个 OpenAI 账号），所以主键是随机 `id`，不是预设 id。
/// API Key **不在这里**：只存 Keychain，账号名由 `apiKeyAccount` 给出。
public struct AIProvider: Codable, Identifiable, Equatable, Sendable {

    public var id: String
    /// 来自哪个预设；自定义服务商为 nil
    public var presetID: String?
    public var name: String
    public var apiProtocol: AIAPIProtocol
    public var baseURL: String
    public var requiresAPIKey: Bool
    /// 已添加、会出现在对话模型选择里的模型
    public var models: [String]
    public var isEnabled: Bool

    public init(
        id: String = UUID().uuidString,
        presetID: String? = nil,
        name: String,
        apiProtocol: AIAPIProtocol = .openAICompatible,
        baseURL: String,
        requiresAPIKey: Bool = true,
        models: [String] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.presetID = presetID
        self.name = name
        self.apiProtocol = apiProtocol
        self.baseURL = baseURL
        self.requiresAPIKey = requiresAPIKey
        self.models = models
        self.isEnabled = isEnabled
    }

    /// 由预设创建
    ///
    /// 只预添加预设的第一个模型：填完 Key 就能直接对话，其余让用户自己挑或自动拉取，
    /// 而不是把一串可能已经过期的模型名全塞进选择器。
    public init(preset: AIProviderPreset) {
        self.init(
            presetID: preset.id,
            name: preset.name,
            apiProtocol: preset.apiProtocol,
            baseURL: preset.baseURL,
            requiresAPIKey: preset.requiresAPIKey,
            models: preset.suggestedModels.first.map { [$0] } ?? []
        )
    }

    /// 自定义服务商：默认 OpenAI 兼容、需要 Key
    public static func custom(name: String = "自定义服务商") -> AIProvider {
        AIProvider(name: name, baseURL: "")
    }

    /// Keychain 账号名
    public var apiKeyAccount: String { AIProvider.apiKeyAccount(for: id) }

    public static func apiKeyAccount(for providerID: String) -> String {
        "ai.apiKey.\(providerID)"
    }

    /// 去掉首尾空白与末尾斜杠后的 Base URL
    public var resolvedBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    /// 列表里显示的名称：空名字回落到预设名或「未命名」
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return presetID.flatMap(AIProviderPresets.preset(id:))?.name ?? "未命名服务商"
    }

    public var preset: AIProviderPreset? {
        presetID.flatMap(AIProviderPresets.preset(id:))
    }

    /// 加一个模型（去空白、去重）；返回是否真的新增
    @discardableResult
    public mutating func addModel(_ model: String) -> Bool {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !models.contains(trimmed) else { return false }
        models.append(trimmed)
        return true
    }

    public mutating func removeModel(_ model: String) {
        models.removeAll { $0 == model }
    }

    /// 能不能用来对话：已启用、有模型、地址非空、需要 Key 时 Key 非空
    public func isUsable(hasAPIKey: Bool) -> Bool {
        guard isEnabled, !models.isEmpty, !resolvedBaseURL.isEmpty else { return false }
        return !requiresAPIKey || hasAPIKey
    }

    /// 组装请求端点
    public func endpoint(model: String, apiKey: String) -> AIEndpoint {
        AIEndpoint(
            apiProtocol: apiProtocol,
            baseURL: resolvedBaseURL,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model,
            requiresAPIKey: requiresAPIKey
        )
    }
}

/// 一次请求要用到的全部连接信息（纯值，可跨 actor 传递）
public struct AIEndpoint: Sendable, Equatable {
    public var apiProtocol: AIAPIProtocol
    public var baseURL: String
    public var apiKey: String
    public var model: String
    /// 缺 Key 时请求前就报错，而不是等服务端回 401
    public var requiresAPIKey: Bool

    public init(
        apiProtocol: AIAPIProtocol, baseURL: String, apiKey: String, model: String,
        requiresAPIKey: Bool = true
    ) {
        self.apiProtocol = apiProtocol
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.requiresAPIKey = requiresAPIKey
    }
}

/// 一个具体的模型（服务商 + 模型名）
public struct AIModelRef: Codable, Hashable, Sendable {
    public var providerID: String
    public var model: String

    public init(providerID: String, model: String) {
        self.providerID = providerID
        self.model = model
    }
}

/// 对话里可选的一个模型，带上显示用的服务商名
public struct AIModelChoice: Identifiable, Hashable, Sendable {
    public let ref: AIModelRef
    public let providerName: String

    public var id: AIModelRef { ref }
    public var model: String { ref.model }

    /// 「服务商 · 模型」
    public var label: String { "\(providerName) · \(ref.model)" }
}
