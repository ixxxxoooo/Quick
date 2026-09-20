// AIWebViewWindowManager.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickUI
import SwiftUI
import WebKit

/// AI WebView 独立窗口管理器
///
/// 每个 AI Provider 一个独立 WKWebView 窗口，窗口关闭只隐藏不销毁，
/// 保持登录态与会话历史（参考 Fasty aiPortalWindowManager 的窗口生命周期设计）。
///
/// 由 `AIPlugin` 持有而**不是单例**：窗口是插件的一部分，插件停用时窗口应当一起收掉。
/// 挂成全局单例就没有人负责它的生命周期，也没人能保证启停成对。
@MainActor
final class AIWebViewWindowManager {

    private let log = QuickLog.plugin(AIPlugin.id)

    /// 各 Provider 的窗口实例
    private var windows: [String: AIWebViewWindow] = [:]

    /// 默认窗口尺寸
    private let defaultWidth: CGFloat = 1100
    private let defaultHeight: CGFloat = 780

    /// 胶囊里置顶按钮的标识
    private static let pinActionID = "pin"

    // MARK: - 窗口生命周期

    /// 打开或聚焦指定 Provider 的窗口
    func openOrFocus(providerId: String) {
        guard let provider = AIProviderRegistry.provider(for: providerId) else {
            log.error("未知 Provider: \(providerId, privacy: .public)")
            return
        }

        if let existing = windows[providerId] {
            existing.panel.makeKeyAndOrderFront(nil)
            existing.panel.orderFrontRegardless()
            log.debug("聚焦窗口: \(provider.name, privacy: .public)")
        } else {
            let window = createWindow(for: provider)
            windows[providerId] = window
            window.panel.makeKeyAndOrderFront(nil)
            window.panel.center()
            log.notice("创建窗口: \(provider.name, privacy: .public)")
        }

        EventBus.shared.post(HidePaletteEvent())
    }

    /// 检查指定 Provider 窗口是否打开
    func isWindowOpen(for providerId: String) -> Bool {
        guard let window = windows[providerId] else { return false }
        return window.panel.isVisible
    }

    /// 隐藏窗口（保持会话）
    func hideWindow(for providerId: String) {
        windows[providerId]?.panel.orderOut(nil)
    }

    /// 销毁窗口（释放 WebView）
    func destroyWindow(for providerId: String) {
        guard let window = windows[providerId] else { return }
        window.panel.onClose = nil
        window.panel.close()
        windows[providerId] = nil
        log.notice("销毁窗口: \(providerId, privacy: .public)")
    }

    /// 收掉所有 AI 窗口（插件停用 / 应用退出时调用）
    func closeAll() {
        guard !windows.isEmpty else { return }
        for (providerId, window) in windows {
            window.panel.onClose = nil
            window.panel.close()
            log.notice("随插件停用关闭窗口: \(providerId, privacy: .public)")
        }
        windows.removeAll()
    }

    /// 刷新页面
    func reloadWindow(for providerId: String) {
        guard let window = windows[providerId] else { return }
        if let provider = AIProviderRegistry.provider(for: providerId) {
            if let url = URL(string: provider.url) {
                window.webView.load(URLRequest(url: url))
            } else {
                window.webView.reload()
            }
        }
    }

    /// 切换窗口置顶
    func toggleAlwaysOnTop(for providerId: String) {
        guard let window = windows[providerId] else { return }
        setAlwaysOnTop(for: providerId, flag: window.panel.level != .floating)
    }

    /// 设置窗口置顶状态
    func setAlwaysOnTop(for providerId: String, flag: Bool) {
        guard let window = windows[providerId] else { return }
        window.panel.level = flag ? .floating : .normal
        window.capsule.setToggle(
            Self.pinActionID,
            isOn: flag,
            tooltip: flag ? "取消置顶" : "窗口置顶"
        )
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

    private func createWindow(for provider: AIProvider) -> AIWebViewWindow {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

        if let url = URL(string: provider.url) {
            webView.load(URLRequest(url: url))
        }

        // `.nonactivatingPanel`：唤出主面板时不要把 AI 窗口一起带到前台。
        // 两者各自独立 —— 用户按 ⌥Space 只是想找东西，不是想切回 AI 页面。
        let panel = AIWebViewPanel(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = provider.name
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .visible
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 600, height: 400)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let providerId = provider.id
        panel.onClose = { [weak panel] in
            panel?.orderOut(nil)
        }

        // 内容视图布局：WebView 铺满 + 悬浮胶囊叠在上面
        let hostView = NSView(frame: panel.contentView?.bounds ?? .zero)
        hostView.autoresizingMask = [.width, .height]
        webView.frame = hostView.bounds
        webView.autoresizingMask = [.width, .height]
        hostView.addSubview(webView)

        // 悬浮胶囊（原生 NSView，不依赖网页 DOM）
        let capsule = FloatingCapsuleView(
            positionKey: "ai.\(providerId)",
            actions: [
                CapsuleAction(
                    id: Self.pinActionID,
                    symbol: "pin",
                    tooltip: "窗口置顶",
                    kind: .toggle
                ) { [weak self] in
                    self?.toggleAlwaysOnTop(for: providerId)
                },
                CapsuleAction(
                    id: "reload",
                    symbol: "arrow.clockwise",
                    tooltip: "刷新网页会话"
                ) { [weak self] in
                    self?.reloadWindow(for: providerId)
                },
                CapsuleAction(
                    id: "external",
                    symbol: "arrow.up.right.square",
                    tooltip: "在浏览器中打开"
                ) { [weak self] in
                    self?.openInBrowser(providerId: providerId)
                },
                CapsuleAction(
                    id: "close",
                    symbol: "xmark",
                    tooltip: "关闭窗口",
                    kind: .destructive
                ) { [weak self] in
                    self?.destroyWindow(for: providerId)
                }
            ])
        hostView.addSubview(capsule)
        capsule.positionInSuperview()

        panel.contentView = hostView

        return AIWebViewWindow(
            panel: panel, webView: webView, providerId: provider.id, capsule: capsule)
    }
}

// MARK: - 窗口数据

struct AIWebViewWindow {
    let panel: AIWebViewPanel
    let webView: WKWebView
    let providerId: String
    let capsule: FloatingCapsuleView
}

/// 自定义 NSPanel，点红绿灯只隐藏不销毁
final class AIWebViewPanel: NSPanel {
    var onClose: (() -> Void)?

    override func close() {
        if let onClose {
            onClose()
        } else {
            super.close()
        }
    }

    /// 非激活面板只需要能拿到键盘输入，不需要成为主窗口 ——
    /// 成为主窗口正是「应用一激活它就被带到前台」的原因。
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
