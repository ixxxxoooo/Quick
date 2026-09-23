// AIServiceTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickPlatform

@Suite("AIService Base URL 校验")
struct AIServiceBaseURLTests {

    /// 自定义服务商的地址是用户手填的：非本机的 http 会让 API Key 随请求头明文出网
    @Test("非本机的 http 自定义地址被拒绝")
    func nonLocalHTTPIsRejected() {
        #expect(
            AIService.baseURLError("http://api.example.com/v1", provider: .custom)
                == .insecureBaseURL("http://api.example.com/v1"))
        #expect(
            AIService.baseURLError("http://192.168.1.10:8080/v1", provider: .custom)
                == .insecureBaseURL("http://192.168.1.10:8080/v1"))
    }

    /// 本机回环不出网，http 也没有泄露面（Ollama 默认就是 http://localhost）
    @Test("本机回环地址允许 http")
    func localHTTPIsAllowed() {
        #expect(AIService.baseURLError("http://localhost:11434/v1", provider: .custom) == nil)
        #expect(AIService.baseURLError("http://127.0.0.1:8080/v1", provider: .custom) == nil)
        #expect(AIService.baseURLError("http://[::1]:8080/v1", provider: .custom) == nil)
    }

    @Test("https 自定义地址不受限")
    func httpsIsAllowed() {
        #expect(AIService.baseURLError("https://api.example.com/v1", provider: .custom) == nil)
    }

    /// 限制只针对 custom：内置服务商的默认地址（如 Ollama 的 http://localhost）不受影响
    @Test("非 custom 服务商不做 http 限制")
    func otherProvidersAreNotChecked() {
        #expect(AIService.baseURLError("http://192.168.1.10/v1", provider: .openai) == nil)
        #expect(AIService.baseURLError("http://localhost:11434/v1", provider: .ollama) == nil)
    }

    @Test("空串与缺 scheme 的地址报 invalidURL")
    func malformedIsInvalid() {
        #expect(AIService.baseURLError("", provider: .custom) == .invalidURL(""))
        #expect(
            AIService.baseURLError("example.com/v1", provider: .custom)
                == .invalidURL("example.com/v1"))
    }
}
