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

    /// 设置页是否允许使用这个 Provider
    ///
    /// 门户卡片、搜索结果、打开动作问的是同一件事，判定只留这一份 —— 抄成两份，
    /// 就会出现「卡片能点、点了没反应」。
    ///
    /// `nonisolated`：搜索结果在无隔离的搜索路径上构造，这里只读 `UserDefaults`。
    nonisolated static func isProviderEnabled(_ providerId: String) -> Bool {
        PluginDefaults.isEnabled(
            PluginSettingKey.AIPortal.providerEnabled(providerId), default: true)
    }

    /// 设置页里被停用的 Provider
    ///
    /// 门户视图拿它把停用的卡片画成停用，而不是画成一张能点的卡片。
    func disabledProviderIDs() -> Set<String> {
        Set(AIProviderRegistry.all.map(\.id).filter { !Self.isProviderEnabled($0) })
    }

    /// 打开或聚焦指定 Provider 的窗口
    ///
    /// 三句都是必需的，少一句就会「唤醒了却不在最前面」：`NSApp.activate` 让应用成为前台
    /// （accessory 应用同样有效），`makeKeyAndOrderFront` 拿到键盘焦点，`orderFrontRegardless`
    /// 让它越过其他应用已经排在前面的窗口 —— 新建的窗口尤其容易因为少了这一句而留在后面。
    ///
    /// - Returns: 窗口是否真的打开了。调用方要照这个说话：面板上那句「已打开」如果无条件弹，
    ///   用户看到的就是「提示成功、什么都没有」，比不提示更糟。
    @discardableResult
    func openOrFocus(providerId: String) -> Bool {
        guard let provider = AIProviderRegistry.provider(for: providerId) else {
            log.error("未知 Provider: \(providerId, privacy: .public)")
            return false
        }
        // 设置页关掉的 Provider 不能被打开：门户卡片与搜索动作都汇聚到这一个入口
        guard Self.isProviderEnabled(provider.id) else {
            log.notice("Provider 已在设置中停用，忽略打开请求: \(providerId, privacy: .public)")
            return false
        }

        let window: AIWebViewWindow
        if let existing = windows[providerId] {
            window = existing
            log.debug("聚焦窗口: \(provider.name, privacy: .public)")
        } else {
            window = createWindow(for: provider)
            windows[providerId] = window
            window.panel.center()
            log.notice("创建窗口: \(provider.name, privacy: .public)")
        }

        NSApp.activate(ignoringOtherApps: true)
        window.panel.makeKeyAndOrderFront(nil)
        window.panel.orderFrontRegardless()
        syncDockPresence()

        EventBus.shared.post(HidePaletteEvent())
        return true
    }

    /// 检查指定 Provider 窗口是否打开
    func isWindowOpen(for providerId: String) -> Bool {
        guard let window = windows[providerId] else { return false }
        return window.panel.isVisible
    }

    /// 隐藏窗口（保持会话）
    func hideWindow(for providerId: String) {
        windows[providerId]?.panel.orderOut(nil)
        syncDockPresence()
    }

    /// 销毁窗口（释放 WebView）
    func destroyWindow(for providerId: String) {
        guard let window = windows[providerId] else { return }
        window.panel.onClose = nil
        window.panel.close()
        windows[providerId] = nil
        syncDockPresence()
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
        syncDockPresence()
    }

    // MARK: - Dock 身份

    /// 已经在 `ActivationPolicyKeeper` 里登记过的 Provider
    private var dockHolders: Set<String> = []

    /// 让「应用要不要 Dock 身份」跟着可见窗口走
    ///
    /// AI 窗口是普通窗口，必须能在 ⌘Tab / Mission Control 里被找回 —— 而 accessory 应用
    /// 根本不在切换器里。所以只要还有一个可见窗口，就暂时占用 Dock 身份；最后一个窗口
    /// 隐藏或销毁时交还，平时仍然是一个不占位的效率工具。
    ///
    /// 隐藏（点红绿灯）也要交还：窗口看不见时没有「找回来」的需求，而 Dock 里挂着一个
    /// 点开什么都没有的图标只会更困惑。
    private func syncDockPresence() {
        let visible = activeProviderIDs()

        for providerId in visible.subtracting(dockHolders) {
            ActivationPolicyKeeper.retain(Self.activationHolder(providerId))
            dockHolders.insert(providerId)
        }
        for providerId in dockHolders.subtracting(visible) {
            ActivationPolicyKeeper.release(Self.activationHolder(providerId))
            dockHolders.remove(providerId)
        }
    }

    /// 该 Provider 在 `ActivationPolicyKeeper` 里的持有者标识
    private static func activationHolder(_ providerId: String) -> String {
        "ai.\(providerId)"
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

    // MARK: - 窗口构造

    /// 造一个 Provider 窗口（不含 WebView、不加载网页）
    ///
    /// 抽成独立方法是为了能直接断言窗口配置 —— 「能不能在 ⌘Tab 里被找回来」全部由这几个
    /// 参数决定，而它们在真的建窗口那条路上要连网加载页面，不适合放进测试。
    ///
    /// - Parameters:
    ///   - provider: 目标 Provider
    ///   - size: 初始尺寸
    /// - Returns: 尚未安装内容视图的窗口
    static func makePanel(provider: AIProvider, size: NSSize) -> AIWebViewPanel {
        let panel = AIWebViewPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        panel.hidesOnDeactivate = false
        panel.identifier = NSUserInterfaceItemIdentifier("quick.ai.\(provider.id)")
        return panel
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

        // **不是非激活面板。** `.nonactivatingPanel` 是给「不该参与应用激活排序」的浮层用的
        // （主面板就是），代价是窗口不进 ⌘Tab / Mission Control，切走之后再也找不回来。
        // AI 窗口是一块用户会持续使用的页面，所以它是**普通窗口**：能成为 key、也能成为 main，
        // 并随可见窗口暂时占用 Dock 身份（见 `syncDockPresence`）。
        let panel = Self.makePanel(
            provider: provider,
            size: NSSize(width: defaultWidth, height: defaultHeight)
        )

        let providerId = provider.id
        // 点红绿灯只是隐藏：保持登录态与会话历史。走 hideWindow 是为了顺带交还 Dock 身份。
        panel.onClose = { [weak self] in
            self?.hideWindow(for: providerId)
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

        // 「窗口默认置顶」只决定新窗口的初始层级，之后用户用胶囊上的图钉随时改
        if PluginDefaults.isEnabled(PluginSettingKey.AIPortal.defaultAlwaysOnTop, default: false) {
            panel.level = .floating
            capsule.setToggle(Self.pinActionID, isOn: true, tooltip: "取消置顶")
        }

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

    /// 普通窗口：能成为主窗口，⌘Tab 切回来时才会到它
    override var canBecomeMain: Bool { true }
}
