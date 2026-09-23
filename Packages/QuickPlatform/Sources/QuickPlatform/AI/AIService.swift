// AIService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 一条对话消息
public struct AIMessage: Sendable, Equatable {

    public enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    public static func system(_ content: String) -> AIMessage { AIMessage(role: .system, content: content) }
    public static func user(_ content: String) -> AIMessage { AIMessage(role: .user, content: content) }
    public static func assistant(_ content: String) -> AIMessage {
        AIMessage(role: .assistant, content: content)
    }
}

/// AI 调用失败的原因
public enum AIError: LocalizedError, Sendable, Equatable {
    case notEnabled
    case missingAPIKey
    case invalidURL(String)
    case insecureBaseURL(String)
    case transport(String)
    case http(status: Int, body: String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .notEnabled:
            return "AI 未启用。请到「设置 › AI 服务」打开开关。"
        case .missingAPIKey:
            return "还没填 API Key。请到「设置 › AI 服务」填写。"
        case .invalidURL(let url):
            return "Base URL 无效：\(url)"
        case .insecureBaseURL(let url):
            return "Base URL 是不加密的 http 且不是本机地址，API Key 会明文出网，已拒绝：\(url)。请改用 https 或 localhost。"
        case .transport(let message):
            return "请求失败：\(message)"
        case .http(let status, let body):
            return body.isEmpty ? "服务返回 \(status)" : "服务返回 \(status)：\(body)"
        case .emptyResponse:
            return "服务返回了空内容。"
        }
    }
}

/// 宿主级 AI 基座
///
/// 一份配置（`AIConfig`）、一个入口：任何插件都能 `import QuickPlatform` 后调用
/// `AIService.chat(...)` 拿到模型回复，不必各自维护 Key / Base URL / 模型。
///
/// **无状态、不是单例**：配置每次现读 `UserDefaults`，调用本身不持有任何东西 ——
/// 所以它是 `enum` + 静态方法，不需要往 `AppCore` 上再挂一个所有者。
///
/// 协议：OpenAI 兼容（OpenAI / DeepSeek / Ollama / 自定义）走 `/chat/completions`；
/// Anthropic 走 `/messages` 并带自己的鉴权头。
public enum AIService {

    private static let log = QuickLog.logger("ai")

    /// 当前配置快照
    public static func currentConfig(from defaults: UserDefaults = .standard) -> AIConfig {
        AIConfig.load(from: defaults)
    }

    /// 发起一次对话，返回助手回复
    public static func chat(messages: [AIMessage]) async throws -> String {
        let config = currentConfig()
        guard config.enabled else { throw AIError.notEnabled }
        if config.provider.requiresAPIKey,
            config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            throw AIError.missingAPIKey
        }
        if let error = baseURLError(config.resolvedBaseURL, provider: config.provider) {
            throw error
        }
        if config.provider == .anthropic {
            return try await anthropicChat(config: config, messages: messages)
        }
        return try await openAIChat(config: config, messages: messages)
    }

    /// 校验 Base URL：不合法、或会让 API Key 明文出网时返回应抛出的错误，否则返回 nil
    ///
    /// 自定义服务商的地址由用户手填：填成非本机的 `http://` 会让 Key 随请求头明文出网，
    /// 这种配置直接拒绝，比事后提醒有效。抽成纯函数是为了不起请求就能直接断言。
    static func baseURLError(_ base: String, provider: AIProviderKind) -> AIError? {
        guard provider == .custom else { return nil }
        guard !base.isEmpty, let url = URL(string: base), url.scheme != nil else {
            return .invalidURL(base)
        }
        guard url.scheme?.lowercased() == "http" else { return nil }
        guard let host = url.host, isLocalHost(host) else {
            return .insecureBaseURL(base)
        }
        return nil
    }

    /// 本机回环地址的 http 不出网，Key 没有明文泄露面
    private static func isLocalHost(_ host: String) -> Bool {
        let lowercased = host.lowercased()
        return lowercased == "localhost" || lowercased == "127.0.0.1" || lowercased == "::1"
            || lowercased.hasSuffix(".localhost")
    }

    /// 连接自检：发一条最短消息，能拿到回复就算通
    public static func testConnection() async throws -> String {
        try await chat(messages: [.user("ping")])
    }

    // MARK: - OpenAI 兼容

    private static func openAIChat(config: AIConfig, messages: [AIMessage]) async throws -> String {
        let base = config.resolvedBaseURL
        guard !base.isEmpty, let url = URL(string: base + "/chat/completions") else {
            throw AIError.invalidURL(config.resolvedBaseURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": config.resolvedModel,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String, !content.isEmpty
        else { throw AIError.emptyResponse }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Anthropic

    private static func anthropicChat(config: AIConfig, messages: [AIMessage]) async throws -> String {
        let base = config.resolvedBaseURL
        guard !base.isEmpty, let url = URL(string: base + "/messages") else {
            throw AIError.invalidURL(config.resolvedBaseURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Key 可能带着粘贴来的首尾空白，与 OpenAI 分支一样先 trim，否则鉴权头永远对不上
        request.setValue(
            config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Anthropic 把 system 放在顶层，不放进 messages
        let system = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n")
        let turns = messages.filter { $0.role != .system }.map {
            ["role": $0.role.rawValue, "content": $0.content]
        }
        var body: [String: Any] = [
            "model": config.resolvedModel,
            "max_tokens": config.maxTokens,
            "messages": turns
        ]
        if !system.isEmpty { body["system"] = system }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let text = content.first?["text"] as? String, !text.isEmpty
        else { throw AIError.emptyResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 传输

    /// 发起请求并按 logging.md 记录：只记 host / 状态码 / 耗时，Key 与正文永远不进日志
    private static func send(_ request: URLRequest) async throws -> Data {
        let host = request.url?.host ?? "unknown"
        log.info("AI 请求发起：\(host, privacy: .public)")
        let signpost = QuickLog.signposter("ai")
        let interval = signpost.beginInterval("AIService.request")
        let started = Date()
        defer { signpost.endInterval("AIService.request", interval) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log.error(
                "AI 请求失败：\(host, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            throw AIError.transport(error.localizedDescription)
        }
        let milliseconds = Date().timeIntervalSince(started) * 1000
        guard let http = response as? HTTPURLResponse else {
            log.error("AI 响应无效：\(host, privacy: .public)")
            throw AIError.transport("无效响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            log.error(
                "AI 服务返回 \(http.statusCode, privacy: .public)：\(host, privacy: .public)，耗时 \(milliseconds, format: .fixed(precision: 0)) ms"
            )
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.http(status: http.statusCode, body: String(body.prefix(400)))
        }
        log.notice(
            "AI 响应 \(http.statusCode, privacy: .public)：\(host, privacy: .public)，耗时 \(milliseconds, format: .fixed(precision: 0)) ms"
        )
        return data
    }
}
