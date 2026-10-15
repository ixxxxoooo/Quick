// AIErrorPageTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginAI

@Suite("AI 错误页")
struct AIErrorPageTests {

    @Test("用户取消的加载不展示错误页")
    func cancelledIsIgnored() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        #expect(!AIErrorPage.shouldShow(for: error))
    }

    @Test("断网等真实失败要展示错误页")
    func offlineIsShown() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(AIErrorPage.shouldShow(for: error))
    }

    @Test("非 URL 域的错误一律展示")
    func otherDomainIsShown() {
        #expect(AIErrorPage.shouldShow(for: NSError(domain: "WebKitErrorDomain", code: 102)))
    }

    @Test("错误页包含重试链接并转义特殊字符")
    func htmlEscapesAndHasRetry() {
        let html = AIErrorPage.html(providerName: "A<b>", message: "x & \"y\"")
        #expect(html.contains("\(AIErrorPage.retryScheme)://reload"))
        #expect(html.contains("A&lt;b&gt;"))
        #expect(html.contains("x &amp; &quot;y&quot;"))
        #expect(!html.contains("A<b>"))
    }
}
