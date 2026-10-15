// AIService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 一条发给模型的消息
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
    case missingAPIKey
    case invalidURL(String)
    case insecureBaseURL(String)
    case transport(String)
    case http(status: Int, body: String)
    /// 服务端在流里（HTTP 200 之后）报的错
    case provider(String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "还没填 API Key。请到「设置 › AI 服务」填写。"
        case .invalidURL(let url):
            return url.isEmpty ? "还没填 Base URL。" : "Base URL 无效：\(url)"
        case .insecureBaseURL(let url):
            return "Base URL 是不加密的 http 且不是本机地址，API Key 会明文出网，已拒绝：\(url)。请改用 https 或 localhost。"
        case .transport(let message):
            return "请求失败：\(message)"
        case .http(let status, let body):
            return body.isEmpty ? "服务返回 \(status)" : "服务返回 \(status)：\(body)"
        case .provider(let message):
            return "服务返回错误：\(message)"
        case .emptyResponse:
            return "服务返回了空内容。"
        }
    }
}

/// 流式响应里的一个事件
public enum AIStreamEvent: Equatable, Sendable {
    /// 一段新增文本
    case text(String)
    /// 服务端表示结束
    case finished
    /// 心跳、元数据、角色声明……对界面没有意义
    case ignored
}

/// 宿主级 AI 基座
///
/// 无状态、不是单例：连接信息由调用方以 `AIEndpoint` 传入（服务商与 Key 由
/// `AIProviderStore` 管），所以它是 `enum` + 静态方法，不需要往 `AppCore` 上再挂所有者。
///
/// 协议：OpenAI 兼容走 `/chat/completions`；Anthropic 走 `/messages` 并带自己的鉴权头。
/// 对话一律走流式 —— 等整段回复生成完再显示，十几秒的空白就是「卡住了」。
///
/// 请求的构造与响应的解析都是纯函数（`makeChatRequest` / `parseStreamLine` /
/// `parseModelIDs`），不起网络就能断言。
public enum AIService {

    private static let log = QuickLog.logger("ai")

    // MARK: - 校验

    /// 校验 Base URL：不合法、或会让 API Key 明文出网时返回应抛出的错误，否则返回 nil
    ///
    /// 地址由用户手填：填成非本机的 `http://` 会让 Key 随请求头明文出网，
    /// 这种配置直接拒绝，比事后提醒有效。
    public static func baseURLError(_ base: String) -> AIError? {
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

    private static func validate(_ endpoint: AIEndpoint) throws {
        if endpoint.requiresAPIKey, endpoint.apiKey.isEmpty { throw AIError.missingAPIKey }
        if let error = baseURLError(endpoint.baseURL) { throw error }
    }

    // MARK: - 请求构造（纯函数）

    /// 构造对话请求
    public static func makeChatRequest(
        endpoint: AIEndpoint, messages: [AIMessage], options: AIConfig, stream: Bool
    ) throws -> URLRequest {
        try validate(endpoint)
        switch endpoint.apiProtocol {
        case .openAICompatible:
            var request = try baseRequest(endpoint, path: "/chat/completions", method: "POST")
            let body: [String: Any] = [
                "model": endpoint.model,
                "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
                "max_tokens": options.maxTokens,
                "temperature": options.temperature,
                "stream": stream
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            return request

        case .anthropic:
            var request = try baseRequest(endpoint, path: "/messages", method: "POST")
            // Anthropic 把 system 放在顶层，不放进 messages
            let system = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n")
            let turns = messages.filter { $0.role != .system }.map {
                ["role": $0.role.rawValue, "content": $0.content]
            }
            var body: [String: Any] = [
                "model": endpoint.model,
                "max_tokens": options.maxTokens,
                "temperature": min(options.temperature, 1),  // Anthropic 的温度上限是 1
                "messages": turns,
                "stream": stream
            ]
            if !system.isEmpty { body["system"] = system }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            return request
        }
    }

    /// 构造「拉取模型列表」请求
    public static func makeModelsRequest(endpoint: AIEndpoint) throws -> URLRequest {
        try validate(endpoint)
        var request = try baseRequest(endpoint, path: "/models", method: "GET")
        if endpoint.apiProtocol == .anthropic {
            // Anthropic 默认一页只给 20 个
            request.url = URL(string: endpoint.baseURL + "/models?limit=1000")
        }
        return request
    }

    private static func baseRequest(
        _ endpoint: AIEndpoint, path: String, method: String
    ) throws -> URLRequest {
        guard let url = URL(string: endpoint.baseURL + path) else {
            throw AIError.invalidURL(endpoint.baseURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        if method == "POST" { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        switch endpoint.apiProtocol {
        case .openAICompatible:
            if !endpoint.apiKey.isEmpty {
                request.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
            }
        case .anthropic:
            request.setValue(endpoint.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        return request
    }

    // MARK: - 响应解析（纯函数）

    /// 解析一行 SSE
    ///
    /// 只关心 `data:` 行；`event:`、注释（`:` 开头）与空行都忽略。
    /// 流里夹带的错误对象会抛出，而不是被当成「空回复」吞掉。
    public static func parseStreamLine(
        _ line: String, apiProtocol: AIAPIProtocol
    ) throws -> AIStreamEvent {
        guard line.hasPrefix("data:") else { return .ignored }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .finished }
        guard let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .ignored }

        // 两家的错误形态：{"error": {"message": ...}} / {"type": "error", "error": {...}}
        if let error = json["error"] {
            let message =
                (error as? [String: Any])?["message"] as? String ?? (error as? String) ?? "未知错误"
            throw AIError.provider(message)
        }

        switch apiProtocol {
        case .openAICompatible:
            let choices = json["choices"] as? [[String: Any]]
            let delta = choices?.first?["delta"] as? [String: Any]
            if let text = delta?["content"] as? String, !text.isEmpty { return .text(text) }
            return .ignored

        case .anthropic:
            switch json["type"] as? String {
            case "content_block_delta":
                let delta = json["delta"] as? [String: Any]
                if let text = delta?["text"] as? String, !text.isEmpty { return .text(text) }
                return .ignored
            case "message_stop":
                return .finished
            default:
                return .ignored
            }
        }
    }

    /// 解析模型列表：兼容 `{"data":[{"id":…}]}`（OpenAI / Anthropic / Ollama 等）
    /// 与 `{"models":[{"name":"models/…"}]}`（Gemini 原生形态）
    public static func parseModelIDs(_ data: Data) throws -> [String] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.emptyResponse
        }
        var ids: [String] = []
        if let items = json["data"] as? [[String: Any]] {
            ids = items.compactMap { $0["id"] as? String }
        } else if let items = json["models"] as? [[String: Any]] {
            ids = items.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }
                .map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
        }
        let unique = Array(Set(ids.filter { !$0.isEmpty })).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        guard !unique.isEmpty else { throw AIError.emptyResponse }
        return unique
    }

    // MARK: - 网络

    /// 流式对话：每个元素是一段新增文本
    ///
    /// 取消消费方的任务（或丢弃这个流）会立刻取消底层请求，不会白白继续生成。
    public static func stream(
        endpoint: AIEndpoint, messages: [AIMessage], options: AIConfig
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeChatRequest(
                        endpoint: endpoint, messages: messages, options: options, stream: true)
                    let host = request.url?.host ?? "unknown"
                    log.info("AI 流式请求发起：\(host, privacy: .public)")
                    let started = Date()

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIError.transport("无效响应")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 400 { break }
                        }
                        log.error(
                            "AI 服务返回 \(http.statusCode, privacy: .public)：\(host, privacy: .public)")
                        throw AIError.http(status: http.statusCode, body: String(body.prefix(400)))
                    }

                    var produced = false
                    lines: for try await line in bytes.lines {
                        switch try parseStreamLine(line, apiProtocol: endpoint.apiProtocol) {
                        case .text(let text):
                            produced = true
                            continuation.yield(text)
                        case .finished:
                            break lines
                        case .ignored:
                            continue
                        }
                    }
                    guard produced else { throw AIError.emptyResponse }

                    let milliseconds = Date().timeIntervalSince(started) * 1000
                    log.notice(
                        "AI 流式响应完成：\(host, privacy: .public)，耗时 \(milliseconds, format: .fixed(precision: 0)) ms"
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch {
                    log.error("AI 请求失败：\(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: AIError.transport(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 拉取服务商当前可用的模型
    public static func fetchModels(endpoint: AIEndpoint) async throws -> [String] {
        let request = try makeModelsRequest(endpoint: endpoint)
        let data = try await send(request)
        return try parseModelIDs(data)
    }

    /// 连接自检：发一条最短消息，能拿到回复就算通，返回回复开头
    public static func testConnection(endpoint: AIEndpoint) async throws -> String {
        var reply = ""
        let options = AIConfig(maxTokens: AIConfig.minMaxTokens, temperature: 0)
        for try await chunk in stream(endpoint: endpoint, messages: [.user("ping")], options: options) {
            reply += chunk
            if reply.count > 40 { break }
        }
        return reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 发起非流式请求并按 logging.md 记录：只记 host / 状态码 / 耗时，Key 与正文永远不进日志
    private static func send(_ request: URLRequest) async throws -> Data {
        let host = request.url?.host ?? "unknown"
        log.info("AI 请求发起：\(host, privacy: .public)")
        let started = Date()

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
