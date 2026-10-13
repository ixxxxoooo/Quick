// AIServiceTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import QuickPlatform

private func endpoint(
    _ protocolKind: AIAPIProtocol = .openAICompatible,
    base: String = "https://api.example.com/v1",
    key: String = "sk-test",
    requiresKey: Bool = true
) -> AIEndpoint {
    AIEndpoint(
        apiProtocol: protocolKind, baseURL: base, apiKey: key, model: "m1", requiresAPIKey: requiresKey)
}

private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite("AIService Base URL 校验")
struct AIServiceBaseURLTests {

    /// 地址是用户手填的：非本机的 http 会让 API Key 随请求头明文出网
    @Test("非本机的 http 地址被拒绝")
    func nonLocalHTTPIsRejected() {
        #expect(
            AIService.baseURLError("http://api.example.com/v1")
                == .insecureBaseURL("http://api.example.com/v1"))
        #expect(
            AIService.baseURLError("http://192.168.1.10:8080/v1")
                == .insecureBaseURL("http://192.168.1.10:8080/v1"))
    }

    /// 本机回环不出网，http 也没有泄露面（Ollama 默认就是 http://localhost）
    @Test("本机回环地址允许 http")
    func localHTTPIsAllowed() {
        #expect(AIService.baseURLError("http://localhost:11434/v1") == nil)
        #expect(AIService.baseURLError("http://127.0.0.1:8080/v1") == nil)
        #expect(AIService.baseURLError("http://[::1]:8080/v1") == nil)
    }

    @Test("https 地址不受限")
    func httpsIsAllowed() {
        #expect(AIService.baseURLError("https://api.example.com/v1") == nil)
    }

    @Test("空串与缺 scheme 的地址报 invalidURL")
    func malformedIsInvalid() {
        #expect(AIService.baseURLError("") == .invalidURL(""))
        #expect(AIService.baseURLError("example.com/v1") == .invalidURL("example.com/v1"))
    }
}

@Suite("AIService 请求构造")
struct AIServiceRequestTests {

    @Test("OpenAI 兼容：路径、Bearer 鉴权、流式开关与消息体")
    func openAIChatRequest() throws {
        let request = try AIService.makeChatRequest(
            endpoint: endpoint(),
            messages: [.system("规则"), .user("你好")],
            options: AIConfig(maxTokens: 512, temperature: 0.3),
            stream: true)

        #expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")

        let body = try jsonBody(request)
        #expect(body["model"] as? String == "m1")
        #expect(body["stream"] as? Bool == true)
        #expect(body["max_tokens"] as? Int == 512)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["system", "user"])
    }

    @Test("无需 Key 的本地服务不带鉴权头")
    func localNoAuthHeader() throws {
        let request = try AIService.makeChatRequest(
            endpoint: endpoint(base: "http://localhost:11434/v1", key: "", requiresKey: false),
            messages: [.user("hi")], options: AIConfig(), stream: true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Anthropic：x-api-key、版本头、system 提到顶层、温度夹到 1")
    func anthropicChatRequest() throws {
        let request = try AIService.makeChatRequest(
            endpoint: endpoint(.anthropic, base: "https://api.anthropic.com/v1"),
            messages: [.system("规则"), .user("问"), .assistant("答"), .user("再问")],
            options: AIConfig(temperature: 1.8), stream: true)

        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

        let body = try jsonBody(request)
        #expect(body["system"] as? String == "规则")
        #expect(body["temperature"] as? Double == 1)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["user", "assistant", "user"])
    }

    @Test("缺 Key、地址不安全或无效时在请求前就报错")
    func validationErrors() {
        #expect(throws: AIError.missingAPIKey) {
            _ = try AIService.makeChatRequest(
                endpoint: endpoint(key: ""), messages: [.user("x")], options: AIConfig(), stream: true)
        }
        #expect(throws: AIError.insecureBaseURL("http://example.com/v1")) {
            _ = try AIService.makeChatRequest(
                endpoint: endpoint(base: "http://example.com/v1"), messages: [.user("x")],
                options: AIConfig(), stream: true)
        }
        #expect(throws: AIError.invalidURL("")) {
            _ = try AIService.makeModelsRequest(endpoint: endpoint(base: ""))
        }
    }

    @Test("模型列表请求：GET /models；Anthropic 带分页上限与自己的鉴权头")
    func modelsRequest() throws {
        let openAI = try AIService.makeModelsRequest(endpoint: endpoint())
        #expect(openAI.httpMethod == "GET")
        #expect(openAI.url?.absoluteString == "https://api.example.com/v1/models")
        #expect(openAI.httpBody == nil)

        let anthropic = try AIService.makeModelsRequest(
            endpoint: endpoint(.anthropic, base: "https://api.anthropic.com/v1"))
        #expect(anthropic.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=1000")
        #expect(anthropic.value(forHTTPHeaderField: "x-api-key") == "sk-test")
    }
}

@Suite("AIService 流式解析")
struct AIServiceStreamParsingTests {

    @Test("OpenAI：增量文本、[DONE]、角色声明与空增量")
    func openAIStream() throws {
        func parse(_ line: String) throws -> AIStreamEvent {
            try AIService.parseStreamLine(line, apiProtocol: .openAICompatible)
        }
        #expect(try parse(#"data: {"choices":[{"delta":{"content":"你好"}}]}"#) == .text("你好"))
        #expect(try parse(#"data:{"choices":[{"delta":{"content":"无空格"}}]}"#) == .text("无空格"))
        #expect(try parse("data: [DONE]") == .finished)
        #expect(try parse(#"data: {"choices":[{"delta":{"role":"assistant"}}]}"#) == .ignored)
        #expect(try parse(#"data: {"choices":[{"delta":{"content":""}}]}"#) == .ignored)
        #expect(try parse(#"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#) == .ignored)
    }

    @Test("SSE 的注释、event 行、空行与非 JSON 数据都被忽略")
    func nonDataLines() throws {
        for line in [": keep-alive", "event: message", "", "data: not-json", "retry: 1000"] {
            #expect(try AIService.parseStreamLine(line, apiProtocol: .openAICompatible) == .ignored)
        }
    }

    @Test("流里夹带的错误会抛出，而不是被当成空回复")
    func errorsInStream() {
        #expect(throws: AIError.provider("rate limited")) {
            _ = try AIService.parseStreamLine(
                #"data: {"error":{"message":"rate limited"}}"#, apiProtocol: .openAICompatible)
        }
        #expect(throws: AIError.provider("overloaded")) {
            _ = try AIService.parseStreamLine(
                #"data: {"type":"error","error":{"type":"overloaded_error","message":"overloaded"}}"#,
                apiProtocol: .anthropic)
        }
    }

    @Test("Anthropic：文本增量、message_stop，其余事件忽略")
    func anthropicStream() throws {
        func parse(_ line: String) throws -> AIStreamEvent {
            try AIService.parseStreamLine(line, apiProtocol: .anthropic)
        }
        #expect(
            try parse(
                #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"嗨"}}"#)
                == .text("嗨"))
        #expect(try parse(#"data: {"type":"message_stop"}"#) == .finished)
        #expect(try parse(#"data: {"type":"message_start","message":{}}"#) == .ignored)
        #expect(try parse(#"data: {"type":"ping"}"#) == .ignored)
        #expect(
            try parse(
                #"data: {"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{"}}"#)
                == .ignored)
    }
}

@Suite("AIService 模型列表解析")
struct AIServiceModelListTests {

    @Test("OpenAI 形态：取 id，去重并按自然顺序排序")
    func openAIShape() throws {
        let json = #"{"data":[{"id":"gpt-4o"},{"id":"gpt-3.5"},{"id":"gpt-10"},{"id":"gpt-4o"},{"id":"gpt-9"}]}"#
        let ids = try AIService.parseModelIDs(Data(json.utf8))
        #expect(ids == ["gpt-3.5", "gpt-4o", "gpt-9", "gpt-10"])
    }

    @Test("Gemini 原生形态：去掉 models/ 前缀")
    func geminiShape() throws {
        let json = #"{"models":[{"name":"models/gemini-2.0-flash"},{"name":"models/gemini-1.5-pro"}]}"#
        #expect(
            try AIService.parseModelIDs(Data(json.utf8)) == ["gemini-1.5-pro", "gemini-2.0-flash"])
    }

    @Test("空列表、缺字段或不是 JSON 都报空响应")
    func invalidShapes() {
        for json in [#"{"data":[]}"#, #"{"foo":1}"#, "[]", "oops"] {
            #expect(throws: (any Error).self) { _ = try AIService.parseModelIDs(Data(json.utf8)) }
        }
    }
}
