// AIWebViewWindowManager.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickUI
import WebKit

/// AI WebView 独立窗口管理器
///
/// 管理每个 AI Provider 的独立 WKWebView 窗口。
/// 窗口关闭时只隐藏不销毁（`hide_on_close` 语义），保持登录态和会话历史。
/// 参考 Fasty aiPortalWindowManager 的窗口生命周期设计。
@MainActor
final class AIWebViewWindowManager {

    /// 单例
    static let shared = AIWebViewWindowManager()

    private let log = QuickLog.module("ai-portal")

    /// 各 Provider 的窗口实例
    private var windows: [String: AIWebViewWindow] = [:]

    /// 默认窗口尺寸
    private let defaultWidth: CGFloat = 1100
    private let defaultHeight: CGFloat = 780

    private init() {}

    // MARK: - 窗口生命周期

    /// 打开或聚焦指定 Provider 的窗口
    ///
    /// - Parameter providerId: Provider 唯一标识
    func openOrFocus(providerId: String) {
        guard let provider = AIProviderRegistry.provider(for: providerId) else {
            log.error("未知 Provider: \(providerId, privacy: .public)")
            return
        }

        if let existing = windows[providerId] {
            // 已有窗口 → 显示并聚焦
            existing.panel.makeKeyAndOrderFront(nil)
            existing.panel.orderFrontRegardless()
            log.debug("聚焦窗口: \(provider.name, privacy: .public)")
        } else {
            // 创建新窗口
            let window = createWindow(for: provider)
            windows[providerId] = window
            window.panel.makeKeyAndOrderFront(nil)
            window.panel.center()
            log.notice("创建窗口: \(provider.name, privacy: .public)")
        }

        // 隐藏 Quick 主面板
        EventBus.shared.post(HidePaletteEvent())
    }

    /// 检查指定 Provider 窗口是否打开
    func isWindowOpen(for providerId: String) -> Bool {
        guard let window = windows[providerId] else { return false }
        return window.panel.isVisible
    }

    /// 关闭指定 Provider 窗口（隐藏，不销毁）
    func hideWindow(for providerId: String) {
        windows[providerId]?.panel.orderOut(nil)
    }

    /// 销毁指定 Provider 窗口（释放 WebView 和内存）
    func destroyWindow(for providerId: String) {
        guard let window = windows[providerId] else { return }
        window.panel.close()
        windows[providerId] = nil
        log.notice("销毁窗口: \(providerId, privacy: .public)")
    }

    /// 刷新指定 Provider 的页面
    func reloadWindow(for providerId: String) {
        guard let window = windows[providerId] else { return }
        if let url = AIProviderRegistry.provider(for: providerId).map({ URL(string: $0.url) }) ?? nil {
            window.webView.load(URLRequest(url: url))
        } else {
            window.webView.reload()
        }
    }

    /// 设置窗口置顶状态
    func setAlwaysOnTop(for providerId: String, flag: Bool) {
        guard let window = windows[providerId] else { return }
        window.panel.level = flag ? .floating : .normal
    }

    /// 在外部浏览器中打开
    func openInBrowser(providerId: String) {
        guard let provider = AIProviderRegistry.provider(for: providerId),
            let url = URL(string: provider.url)
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// 获取所有已打开窗口的 Provider ID
    func activeProviderIDs() -> Set<String> {
        Set(windows.filter { $0.value.panel.isVisible }.keys)
    }

    // MARK: - 窗口创建

    /// 创建 Provider 的独立 WebView 窗口
    private func createWindow(for provider: AIProvider) -> AIWebViewWindow {
        // 配置 WKWebView
        let config = WKWebViewConfiguration()
        // 使用默认持久化数据存储（保持 Cookie 和登录态）
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

        // 加载 URL
        if let url = URL(string: provider.url) {
            webView.load(URLRequest(url: url))
        }

        // 创建面板
        let panel = AIWebViewPanel(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = provider.name
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .visible
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 600, height: 400)
        panel.isReleasedWhenClosed = false

        // 窗口关闭 → 隐藏而非销毁
        panel.onClose = { [weak panel] in
            panel?.orderOut(nil)
        }

        // 内容视图
        let hostView = NSView(frame: panel.contentView?.bounds ?? .zero)
        hostView.autoresizingMask = [.width, .height]
        webView.frame = hostView.bounds
        webView.autoresizingMask = [.width, .height]
        hostView.addSubview(webView)
        panel.contentView = hostView

        return AIWebViewWindow(panel: panel, webView: webView, providerId: provider.id)
    }
}

// MARK: - 窗口和面板数据结构

/// 一个 Provider 的窗口实例
struct AIWebViewWindow {
    let panel: AIWebViewPanel
    let webView: WKWebView
    let providerId: String
}

/// 自定义 NSPanel，关闭时隐藏而非销毁
final class AIWebViewPanel: NSPanel {
    var onClose: (() -> Void)?

    override func close() {
        if let onClose {
            onClose()
        } else {
            super.close()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
