// AIWebViewWindowManager.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickUI
import SwiftUI
import WebKit

/// AI WebView 窗口管理器
///
/// 支持两种模式：
/// - **独立窗口**（默认）：每个 Provider 一个独立窗口
/// - **聚合窗口**：所有 Provider 合并到一个窗口，标签栏嵌入标题栏
///
/// 模式通过设置 `ai.mergeWindows` 切换。窗口位置和大小会持久化。
///
/// 由 `AIPlugin` 持有而**不是单例**：窗口是插件的一部分，插件停用时窗口应当一起收掉。
@MainActor
final class AIWebViewWindowManager {

    private let log = QuickLog.plugin(AIPlugin.id)

    /// 各 Provider 的 WebView（按需创建，保持登录态）
    private var webViews: [String: WKWebView] = [:]

    // MARK: - 独立窗口模式

    /// 独立窗口模式下每个 Provider 的窗口
    private var separateWindows: [String: AIWebViewWindow] = [:]

    // MARK: - 聚合窗口模式

    /// 聚合窗口的面板
    private var mergedPanel: AIWebViewPanel?

    /// 聚合模式标签栏（嵌入标题栏）
    private var titleTabBar: AITitleTabBarView?

    /// 当前选中的 Provider id（聚合模式）
    private(set) var activeProviderID: String?

    /// 聚合模式内容容器
    private var contentContainer: NSView?

    /// 聚合模式悬浮胶囊
    private var mergedCapsule: FloatingCapsuleView?

    /// 默认窗口尺寸
    private let defaultWidth: CGFloat = 1100
    private let defaultHeight: CGFloat = 780

    /// 独立窗口默认尺寸
    private let separateWidth: CGFloat = 1000
    private let separateHeight: CGFloat = 700

    /// 窗口位置/大小持久化键前缀
    private static let mergedFrameKey = "quick.ai.aggregated.frame"
    private static let separateFramePrefix = "quick.ai.separate."

    /// 胶囊里置顶按钮的标识
    private static let pinActionID = "pin"

    // MARK: - 模式查询

    /// 是否处于聚合模式
    var isMergeMode: Bool {
        PluginDefaults.isEnabled(PluginSettingKey.AIPortal.mergeWindows, default: false)
    }

    // MARK: - 窗口生命周期

    /// 设置页是否允许使用这个 Provider
    nonisolated static func isProviderEnabled(_ providerId: String) -> Bool {
        PluginDefaults.isEnabled(
            PluginSettingKey.AIPortal.providerEnabled(providerId), default: true)
    }

    /// 设置页里被停用的 Provider
    func disabledProviderIDs() -> Set<String> {
        Set(AIProviderRegistry.all.map(\.id).filter { !Self.isProviderEnabled($0) })
    }

    /// 打开或聚焦指定 Provider
    @discardableResult
    func openOrFocus(providerId: String) -> Bool {
        guard let provider = AIProviderRegistry.provider(for: providerId) else {
            log.error("未知 Provider: \(providerId, privacy: .public)")
            return false
        }
        guard Self.isProviderEnabled(provider.id) else {
            log.notice("Provider 已在设置中停用: \(providerId, privacy: .public)")
            return false
        }

        if isMergeMode {
            return openOrFocusMerged(provider: provider)
        } else {
            return openOrFocusSeparate(provider: provider)
        }
    }

    /// 检查指定 Provider 窗口是否打开
    func isWindowOpen(for providerId: String) -> Bool {
        if isMergeMode {
            guard let panel = mergedPanel, panel.isVisible else { return false }
            return activeProviderID == providerId
        } else {
            return separateWindows[providerId]?.panel.isVisible ?? false
        }
    }

    /// 切换 Provider 窗口显隐
    @discardableResult
    func toggle(providerId: String) -> Bool {
        if isMergeMode {
            if let panel = mergedPanel, panel.isVisible, activeProviderID == providerId {
                hideWindow(for: providerId)
                log.notice("切换：隐藏聚合窗口 \(providerId, privacy: .public)")
                return false
            }
        } else {
            if let win = separateWindows[providerId], win.panel.isVisible {
                hideWindow(for: providerId)
                log.notice("切换：隐藏独立窗口 \(providerId, privacy: .public)")
                return false
            }
        }
        return openOrFocus(providerId: providerId)
    }

    /// 隐藏窗口
    func hideWindow(for providerId: String) {
        if isMergeMode {
            saveMergedFrame()
            mergedPanel?.orderOut(nil)
            syncDockPresence()
        } else {
            if let win = separateWindows[providerId] {
                saveSeparateFrame(providerId: providerId, panel: win.panel)
                win.panel.orderOut(nil)
                syncDockPresence()
            }
        }
    }

    /// 关闭某个 Provider（销毁 WebView）
    func destroyWindow(for providerId: String) {
        webViews[providerId]?.stopLoading()
        webViews[providerId] = nil

        if isMergeMode {
            titleTabBar?.removeTab(providerId)
            if activeProviderID == providerId {
                let remaining = AIProviderRegistry.all.filter {
                    Self.isProviderEnabled($0.id) && webViews[$0.id] != nil
                }
                if let next = remaining.first {
                    switchToTab(next.id)
                } else {
                    activeProviderID = nil
                    mergedPanel?.orderOut(nil)
                }
            }
        } else {
            if let win = separateWindows.removeValue(forKey: providerId) {
                win.panel.onClose = nil
                win.panel.close()
            }
        }
        syncDockPresence()
        log.notice("销毁: \(providerId, privacy: .public)")
    }

    /// 收掉所有窗口
    func closeAll() {
        saveMergedFrame()
        for (id, webView) in webViews {
            webView.stopLoading()
            log.notice("关闭: \(id, privacy: .public)")
        }
        webViews.removeAll()
        mergedCapsule = nil
        titleTabBar = nil
        if let panel = mergedPanel {
            panel.onClose = nil
            panel.close()
        }
        mergedPanel = nil
        contentContainer = nil
        activeProviderID = nil

        for (id, win) in separateWindows {
            saveSeparateFrame(providerId: id, panel: win.panel)
            win.panel.onClose = nil
            win.panel.close()
        }
        separateWindows.removeAll()
        syncDockPresence()
    }

    /// 模式切换时重建窗口
    func rebuildForModeChange() {
        let openProviders = Array(webViews.keys)
        closeAll()
        for id in openProviders {
            openOrFocus(providerId: id)
        }
    }

    // MARK: - Dock 身份

    private var hasDockPresence = false

    private func syncDockPresence() {
        let anyVisible: Bool
        if isMergeMode {
            anyVisible = mergedPanel?.isVisible ?? false
        } else {
            anyVisible = separateWindows.values.contains { $0.panel.isVisible }
        }
        if anyVisible, !hasDockPresence {
            ActivationPolicyKeeper.retain("ai.aggregated")
            hasDockPresence = true
        } else if !anyVisible, hasDockPresence {
            ActivationPolicyKeeper.release("ai.aggregated")
            hasDockPresence = false
        }
    }

    /// 刷新页面
    func reloadWindow(for providerId: String) {
        guard let webView = webViews[providerId] else { return }
        if let provider = AIProviderRegistry.provider(for: providerId),
            let url = URL(string: provider.url)
        {
            webView.load(URLRequest(url: url))
        } else {
            webView.reload()
        }
    }

    /// 获取所有已打开标签的 Provider ID
    func activeProviderIDs() -> Set<String> {
        if isMergeMode {
            guard let panel = mergedPanel, panel.isVisible else { return [] }
            return Set(webViews.keys)
        } else {
            return Set(separateWindows.filter { $0.value.panel.isVisible }.map(\.key))
        }
    }

    // MARK: - 独立窗口模式

    private func openOrFocusSeparate(provider: AIProvider) -> Bool {
        ensureWebView(for: provider)

        if let win = separateWindows[provider.id] {
            NSApp.activate(ignoringOtherApps: true)
            win.panel.makeKeyAndOrderFront(nil)
            win.panel.orderFrontRegardless()
            syncDockPresence()
            EventBus.shared.post(HidePaletteEvent())
            return true
        }

        guard let webView = webViews[provider.id] else { return false }

        let panel = AIWebViewPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: separateWidth, height: separateHeight)),
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

        panel.onClose = { [weak self] in
            guard let self else { return }
            self.saveSeparateFrame(providerId: provider.id, panel: panel)
            panel.orderOut(nil)
            self.syncDockPresence()
        }

        restoreSeparateFrame(providerId: provider.id, panel: panel)

        // 内容布局
        let hostView = NSView(frame: panel.contentView?.bounds ?? .zero)
        hostView.autoresizingMask = [.width, .height]

        webView.frame = hostView.bounds
        webView.autoresizingMask = [.width, .height]
        hostView.addSubview(webView)

        // 悬浮胶囊
        let capsule = makeCapsule(positionKey: "ai.\(provider.id)", forMerged: false, providerId: provider.id)
        hostView.addSubview(capsule)
        capsule.positionInSuperview()

        if PluginDefaults.isEnabled(PluginSettingKey.AIPortal.defaultAlwaysOnTop, default: false) {
            panel.level = .floating
            capsule.setToggle(Self.pinActionID, isOn: true, tooltip: "取消置顶")
        }

        panel.contentView = hostView

        let win = AIWebViewWindow(panel: panel, webView: webView, providerId: provider.id, capsule: capsule)
        separateWindows[provider.id] = win

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        syncDockPresence()
        EventBus.shared.post(HidePaletteEvent())
        log.notice("打开独立窗口: \(provider.name, privacy: .public)")
        return true
    }

    // MARK: - 聚合窗口模式

    private func openOrFocusMerged(provider: AIProvider) -> Bool {
        ensureMergedWindow()
        ensureWebView(for: provider)
        switchToTab(provider.id)

        guard let panel = mergedPanel else { return false }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        syncDockPresence()

        EventBus.shared.post(HidePaletteEvent())
        log.notice("聚焦标签: \(provider.name, privacy: .public)")
        return true
    }

    /// 确保聚合窗口已创建（标签栏直接嵌入标题栏，与红绿灯同行）
    private func ensureMergedWindow() {
        guard mergedPanel == nil else { return }

        let newPanel = AIWebViewPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: defaultWidth, height: defaultHeight)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.title = "AI 聚合"
        newPanel.titlebarAppearsTransparent = true
        newPanel.titleVisibility = .hidden
        newPanel.isMovableByWindowBackground = true
        newPanel.minSize = NSSize(width: 600, height: 400)
        newPanel.isReleasedWhenClosed = false
        newPanel.hidesOnDeactivate = false
        newPanel.identifier = NSUserInterfaceItemIdentifier("quick.ai.aggregated")

        newPanel.onClose = { [weak self] in
            self?.saveMergedFrame()
            self?.mergedPanel?.orderOut(nil)
            self?.syncDockPresence()
        }

        restoreMergedFrame(newPanel)

        // 标签栏直接嵌入标题栏（与红绿灯同行）
        let tabBar = AITitleTabBarView(onSelect: { [weak self] id in
            self?.switchToTab(id)
        }, onClose: { [weak self] id in
            self?.destroyWindow(for: id)
        })
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        // 找到标题栏容器：红绿灯的父视图就是标题栏
        // themeFrame → titlebar container
        if let titlebarContainer = newPanel.standardWindowButton(.closeButton)?.superview?.superview {
            titlebarContainer.addSubview(tabBar)
            // 红绿灯区域约 70pt，标签栏从其右侧开始，填满标题栏剩余宽度
            NSLayoutConstraint.activate([
                tabBar.leadingAnchor.constraint(
                    equalTo: titlebarContainer.leadingAnchor,
                    constant: DesignTokens.Size.aiTitleBarTabLeading),
                tabBar.trailingAnchor.constraint(equalTo: titlebarContainer.trailingAnchor),
                tabBar.topAnchor.constraint(equalTo: titlebarContainer.topAnchor),
                tabBar.bottomAnchor.constraint(equalTo: titlebarContainer.bottomAnchor),
            ])
        }

        // 内容区域（fullSizeContentView 模式下内容延伸到标题栏后面）
        let hostView = NSView(frame: newPanel.contentView?.bounds ?? .zero)
        hostView.autoresizingMask = [.width, .height]

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: hostView.topAnchor),
            container.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
        ])

        // 悬浮胶囊
        let capsuleView = makeCapsule(positionKey: "ai.aggregated", forMerged: true)
        hostView.addSubview(capsuleView)
        capsuleView.positionInSuperview()

        if PluginDefaults.isEnabled(PluginSettingKey.AIPortal.defaultAlwaysOnTop, default: false) {
            newPanel.level = .floating
            capsuleView.setToggle(Self.pinActionID, isOn: true, tooltip: "取消置顶")
        }

        newPanel.contentView = hostView

        mergedPanel = newPanel
        titleTabBar = tabBar
        contentContainer = container
        mergedCapsule = capsuleView

        log.notice("创建聚合窗口")
    }

    /// 确保某个 Provider 的 WebView 已创建
    private func ensureWebView(for provider: AIProvider) {
        guard webViews[provider.id] == nil else { return }

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

        webViews[provider.id] = webView

        if isMergeMode {
            titleTabBar?.addTab(id: provider.id, title: provider.name, icon: provider.icon)
        }
    }

    /// 聚合模式：切换到指定标签页
    private func switchToTab(_ providerId: String) {
        guard let container = contentContainer,
            let webView = webViews[providerId]
        else { return }

        container.subviews.forEach { $0.removeFromSuperview() }

        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)

        activeProviderID = providerId
        titleTabBar?.selectTab(providerId)

        if let provider = AIProviderRegistry.provider(for: providerId) {
            mergedPanel?.title = provider.name
        }
    }

    // MARK: - 胶囊构造

    private func makeCapsule(positionKey: String, forMerged: Bool, providerId: String? = nil) -> FloatingCapsuleView {
        FloatingCapsuleView(
            positionKey: positionKey,
            actions: [
                CapsuleAction(
                    id: Self.pinActionID,
                    symbol: "pin",
                    tooltip: "窗口置顶",
                    kind: .toggle
                ) { [weak self] in
                    self?.toggleAlwaysOnTop(forMerged: forMerged, providerId: providerId)
                },
                CapsuleAction(
                    id: "reload",
                    symbol: "arrow.clockwise",
                    tooltip: "刷新当前页面"
                ) { [weak self] in
                    let id = forMerged ? self?.activeProviderID : providerId
                    guard let id else { return }
                    self?.reloadWindow(for: id)
                },
                CapsuleAction(
                    id: "external",
                    symbol: "arrow.up.right.square",
                    tooltip: "在浏览器中打开"
                ) { [weak self] in
                    let id = forMerged ? self?.activeProviderID : providerId
                    guard let id else { return }
                    self?.openInBrowser(providerId: id)
                },
                CapsuleAction(
                    id: "close",
                    symbol: "xmark",
                    tooltip: forMerged ? "关闭当前标签" : "关闭窗口",
                    kind: .destructive
                ) { [weak self] in
                    let id = forMerged ? self?.activeProviderID : providerId
                    guard let id else { return }
                    self?.destroyWindow(for: id)
                },
            ])
    }

    // MARK: - 窗口置顶

    func toggleAlwaysOnTop(forMerged: Bool = true, providerId: String? = nil) {
        if forMerged {
            guard let panel = mergedPanel else { return }
            let newState = panel.level != .floating
            panel.level = newState ? .floating : .normal
            mergedCapsule?.setToggle(Self.pinActionID, isOn: newState, tooltip: newState ? "取消置顶" : "窗口置顶")
        } else if let id = providerId, let win = separateWindows[id] {
            let newState = win.panel.level != .floating
            win.panel.level = newState ? .floating : .normal
            win.capsule.setToggle(Self.pinActionID, isOn: newState, tooltip: newState ? "取消置顶" : "窗口置顶")
        }
    }

    /// 旧接口兼容
    func toggleAlwaysOnTop() {
        toggleAlwaysOnTop(forMerged: true)
    }

    /// 设置窗口置顶状态
    func setAlwaysOnTop(for providerId: String, flag: Bool) {
        if isMergeMode {
            guard let panel = mergedPanel else { return }
            panel.level = flag ? .floating : .normal
            mergedCapsule?.setToggle(Self.pinActionID, isOn: flag, tooltip: flag ? "取消置顶" : "窗口置顶")
        } else if let win = separateWindows[providerId] {
            win.panel.level = flag ? .floating : .normal
            win.capsule.setToggle(Self.pinActionID, isOn: flag, tooltip: flag ? "取消置顶" : "窗口置顶")
        }
    }

    /// 在外部浏览器中打开
    func openInBrowser(providerId: String) {
        guard let provider = AIProviderRegistry.provider(for: providerId),
            let url = URL(string: provider.url)
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 窗口位置持久化（聚合模式）

    private func saveMergedFrame() {
        guard let panel = mergedPanel else { return }
        let frame = panel.frame
        UserDefaults.standard.set(
            ["x": frame.origin.x, "y": frame.origin.y,
             "w": frame.size.width, "h": frame.size.height],
            forKey: Self.mergedFrameKey
        )
    }

    private func restoreMergedFrame(_ panel: AIWebViewPanel) {
        if let saved = UserDefaults.standard.dictionary(forKey: Self.mergedFrameKey),
            let x = saved["x"] as? CGFloat,
            let y = saved["y"] as? CGFloat,
            let w = saved["w"] as? CGFloat,
            let h = saved["h"] as? CGFloat
        {
            let frame = NSRect(x: x, y: y, width: max(w, 600), height: max(h, 400))
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                panel.setFrame(frame, display: false)
                return
            }
        }
        panel.center()
    }

    // MARK: - 窗口位置持久化（独立模式）

    private func saveSeparateFrame(providerId: String, panel: AIWebViewPanel) {
        let frame = panel.frame
        UserDefaults.standard.set(
            ["x": frame.origin.x, "y": frame.origin.y,
             "w": frame.size.width, "h": frame.size.height],
            forKey: Self.separateFramePrefix + providerId + ".frame"
        )
    }

    private func restoreSeparateFrame(providerId: String, panel: AIWebViewPanel) {
        let key = Self.separateFramePrefix + providerId + ".frame"
        if let saved = UserDefaults.standard.dictionary(forKey: key),
            let x = saved["x"] as? CGFloat,
            let y = saved["y"] as? CGFloat,
            let w = saved["w"] as? CGFloat,
            let h = saved["h"] as? CGFloat
        {
            let frame = NSRect(x: x, y: y, width: max(w, 600), height: max(h, 400))
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                panel.setFrame(frame, display: false)
                return
            }
        }
        panel.center()
    }

    // MARK: - 测试用工厂

    /// 构建面板（仅用于测试断言窗口配置）
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
}

// MARK: - 标题栏标签视图

/// 嵌入标题栏的标签栏，用于聚合模式
///
/// 每个打开的 Provider 一个标签项，支持点击切换和关闭
@MainActor
final class AITitleTabBarView: NSView {

    private let onSelect: (String) -> Void
    private let onClose: (String) -> Void
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private var tabs: [(id: String, view: AITabItemView)] = []
    private var selectedID: String?

    init(onSelect: @escaping (String) -> Void, onClose: @escaping (String) -> Void) {
        self.onSelect = onSelect
        self.onClose = onClose
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    private func setupViews() {
        // 标题栏内：不画自己的背景，不画分隔线
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = DesignTokens.Size.aiTabItemSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = stackView
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.xs),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Spacing.sm),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
        ])
    }

    func addTab(id: String, title: String, icon: String) {
        guard !tabs.contains(where: { $0.id == id }) else { return }
        let tab = AITabItemView(
            id: id, title: title, icon: icon,
            onSelect: { [weak self] in self?.onSelect(id) },
            onClose: { [weak self] in self?.onClose(id) }
        )
        tabs.append((id: id, view: tab))
        stackView.addArrangedSubview(tab)
    }

    func removeTab(_ id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index].view
        stackView.removeArrangedSubview(tab)
        tab.removeFromSuperview()
        tabs.remove(at: index)
    }

    func selectTab(_ id: String) {
        selectedID = id
        for (tabID, view) in tabs {
            view.setSelected(tabID == id)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
    }
}

/// 标签栏里的单个标签项
private final class AITabItemView: NSView {

    private let id: String
    private let onSelect: () -> Void
    private let onClose: () -> Void
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var isSelected = false
    private var isHovered = false

    init(id: String, title: String, icon: String, onSelect: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.id = id
        self.onSelect = onSelect
        self.onClose = onClose
        super.init(frame: .zero)
        setupViews(title: title, icon: icon)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    private func setupViews(title: String, icon: String) {
        wantsLayer = true
        layer?.cornerRadius = DesignTokens.Radius.barControl

        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = NSColor(DesignTokens.Colors.aiTabText)
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭标签")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.isBordered = false
        closeButton.bezelStyle = .accessoryBarAction
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.toolTip = "关闭标签"
        closeButton.isHidden = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(closeButton)

        let closeSize = DesignTokens.Size.aiTabCloseSize
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Size.aiTabItemPaddingH),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: DesignTokens.Size.aiTabIconSize),
            iconView.heightAnchor.constraint(equalToConstant: DesignTokens.Size.aiTabIconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: DesignTokens.Spacing.xs),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -DesignTokens.Spacing.xxs),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Spacing.sm),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: closeSize),
            closeButton.heightAnchor.constraint(equalToConstant: closeSize),

            widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            widthAnchor.constraint(lessThanOrEqualToConstant: 160),
            heightAnchor.constraint(equalToConstant: DesignTokens.Size.aiTitleBarTabHeight),
        ])
        translatesAutoresizingMaskIntoConstraints = false
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        refreshAppearance()
    }

    @objc private func handleClose() {
        onClose()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect()
        super.mouseDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
    }

    override func mouseEntered(with _: NSEvent) {
        isHovered = true
        closeButton.isHidden = false
        refreshAppearance()
    }

    override func mouseExited(with _: NSEvent) {
        isHovered = false
        closeButton.isHidden = !isSelected
        refreshAppearance()
    }

    private func refreshAppearance() {
        if isSelected {
            layer?.backgroundColor = NSColor(DesignTokens.Colors.aiTabSelected).cgColor
            titleLabel.textColor = NSColor(DesignTokens.Colors.aiTabSelectedText)
            iconView.contentTintColor = NSColor(DesignTokens.Colors.aiTabSelectedText)
            closeButton.isHidden = false
        } else if isHovered {
            layer?.backgroundColor = NSColor(DesignTokens.Colors.aiTabHover).cgColor
            titleLabel.textColor = NSColor(DesignTokens.Colors.aiTabText)
            iconView.contentTintColor = NSColor(DesignTokens.Colors.aiTabText)
        } else {
            layer?.backgroundColor = nil
            titleLabel.textColor = NSColor(DesignTokens.Colors.aiTabText)
            iconView.contentTintColor = NSColor(DesignTokens.Colors.aiTabText)
            closeButton.isHidden = true
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
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

    /// ⌘W 关闭窗口
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
            let chars = event.charactersIgnoringModifiers,
            chars.lowercased() == "w"
        {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
