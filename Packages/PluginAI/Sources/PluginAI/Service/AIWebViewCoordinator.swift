// AIWebViewCoordinator.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import WebKit

/// AI WebView 的导航 / UI 代理
///
/// 没有这层代理时，WKWebView 会有这些「静默坏掉」的行为：
/// - 网页进程崩溃后一直白屏；
/// - 断网或域名解析失败后只有空白，没有任何提示；
/// - `target=_blank` 的链接（登录跳转、分享链接）点了没反应；
/// - 跳出站点的外部链接把 AI 页面本身导航走了；
/// - 网页里的「上传文件」按钮不弹选择面板。
///
/// WebKit 对代理只持弱引用，所以由 `AIWebViewWindowManager` 持有同一个实例。
@MainActor
final class AIWebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

    private let log = QuickLog.plugin(AIPlugin.id)

    /// 外部链接与新窗口的分流（交给系统默认浏览器）。协调器是 WebKit 唯一的代理，
    /// 把这两类导航转交给它，避免再挂第二个代理造成互相覆盖。
    private let linkHandler = AIWebViewNavigationHandler()

    /// 取 WebView 对应的 Provider（用于重试和错误页标题）
    var providerResolver: (WKWebView) -> AIProvider? = { _ in nil }

    // MARK: - WKNavigationDelegate

    /// 网页进程崩溃（通常是内存压力）：直接重新加载，别让用户面对白屏
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("网页进程已终止，自动重新加载: \(webView.url?.host ?? "-", privacy: .public)")
        webView.reload()
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: any Error
    ) {
        showErrorPage(in: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
        showErrorPage(in: webView, error: error)
    }

    /// 先拦截错误页上的「重试」链接，其余交给外部链接分流
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.request.url?.scheme == AIErrorPage.retryScheme {
            decisionHandler(.cancel)
            reloadProvider(webView)
        } else {
            linkHandler.webView(
                webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
        }
    }

    private func showErrorPage(in webView: WKWebView, error: any Error) {
        guard AIErrorPage.shouldShow(for: error) else { return }
        let name = providerResolver(webView)?.name ?? "页面"
        log.error("页面加载失败: \(name, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        webView.loadHTMLString(
            AIErrorPage.html(providerName: name, message: error.localizedDescription), baseURL: nil)
    }

    private func reloadProvider(_ webView: WKWebView) {
        if let provider = providerResolver(webView), let url = URL(string: provider.url) {
            webView.load(URLRequest(url: url))
        } else {
            webView.reload()
        }
    }

    // MARK: - WKUIDelegate

    /// `target=_blank` / `window.open`：交给系统默认浏览器，不在应用内另开窗口
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        linkHandler.webView(
            webView, createWebViewWith: configuration, for: navigationAction,
            windowFeatures: windowFeatures)
    }

    /// 网页里的「上传文件」：弹出系统选择面板
    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        if let window = webView.window {
            panel.beginSheetModal(for: window) { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        } else {
            completionHandler(panel.runModal() == .OK ? panel.urls : nil)
        }
    }
}
