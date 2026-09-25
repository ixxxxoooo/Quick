// AIWebViewWindowManager.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickUI
import SwiftUI
import WebKit

/// AI WebView 聚合窗口管理器
///
/// 所有 AI Provider 聚合到一个窗口中，通过标签页切换。窗口位置和大小会持久化，
/// 下次打开恢复到上次的状态。
///
/// 由 `AIPlugin` 持有而**不是单例**：窗口是插件的一部分，插件停用时窗口应当一起收掉。
@MainActor
final class AIWebViewWindowManager {

    private let log = QuickLog.plugin(AIPlugin.id)

    /// 聚合窗口的面板
    private var panel: AIWebViewPanel?

    /// 各 Provider 的 WebView（按需创建，保持登录态）
    private var webViews: [String: WKWebView] = [:]

    /// 标签栏视图
    private var tabBarView: AITabBarView?

    /// 当前选中的 Provider id
    private(set) var activeProviderID: String?

    /// 窗口内容容器
    private var contentContainer: NSView?

    /// 悬浮胶囊
    private var capsule: FloatingCapsuleView?

    /// 默认窗口尺寸
    private let defaultWidth: CGFloat = 1100
    private let defaultHeight: CGFloat = 780

    /// 窗口位置/大小持久化键
    private static let frameKey = "quick.ai.aggregated.frame"

    /// 胶囊里置顶按钮的标识
    private static let pinActionID = "pin"

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

    /// 打开或聚焦指定 Provider 的标签
    @discardableResult
    func openOrFocus(providerId: String) -> Bool {
        guard let provider = AIProviderRegistry.provider(for: providerId) else {
            log.error("未知 Provider: \(providerId, privacy: .public)")
            return false
        }
        guard Self.isProviderEnabled(provider.id) else {
            log.notice("Provider 已在设置中停用，忽略打开请求: \(providerId, privacy: .public)")
            return false
        }

        ensureWindow()
        ensureWebView(for: provider)
        switchToTab(providerId)

        guard let panel else { return false }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        syncDockPresence()

        EventBus.shared.post(HidePaletteEvent())
        log.notice("聚焦标签: \(provider.name, privacy: .public)")
        return true
    }

    /// 检查指定 Provider 窗口是否打开（即标签页是否激活且窗口可见）
    func isWindowOpen(for providerId: String) -> Bool {
        guard let panel, panel.isVisible else { return false }
        return activeProviderID == providerId
    }

    /// 切换 Provider 窗口显隐
    @discardableResult
    func toggle(providerId: String) -> Bool {
        if let panel, panel.isVisible, activeProviderID == providerId {
            hideWindow(for: providerId)
            log.notice("快捷键切换：隐藏聚合窗口 \(providerId, privacy: .public)")
            return false
        }
        return openOrFocus(providerId: providerId)
    }

    /// 隐藏窗口
    func hideWindow(for _: String) {
        panel?.orderOut(nil)
        syncDockPresence()
    }

    /// 关闭某个 Provider 标签（从标签栏移除，销毁 WebView）
    func destroyWindow(for providerId: String) {
        webViews[providerId]?.stopLoading()
        webViews[providerId] = nil
        tabBarView?.removeTab(providerId)

        if activeProviderID == providerId {
            let enabledProviders = AIProviderRegistry.all.filter { Self.isProviderEnabled($0.id) }
            let remaining = enabledProviders.filter { webViews[$0.id] != nil }
            if let next = remaining.first {
                switchToTab(next.id)
            } else {
                activeProviderID = nil
                panel?.orderOut(nil)
            }
        }
        syncDockPresence()
        log.notice("销毁标签: \(providerId, privacy: .public)")
    }

    /// 收掉聚合窗口（插件停用 / 应用退出时调用）
    func closeAll() {
        saveWindowFrame()
        for (id, webView) in webViews {
            webView.stopLoading()
            log.notice("随插件停用关闭标签: \(id, privacy: .public)")
        }
        webViews.removeAll()
        capsule = nil
        tabBarView = nil
        if let panel {
            panel.onClose = nil
            panel.close()
        }
        panel = nil
        contentContainer = nil
        activeProviderID = nil
        syncDockPresence()
    }

    // MARK: - Dock 身份

    private var hasDockPresence = false

    /// 只要聚合窗口可见，就暂时占用 Dock 身份
    private func syncDockPresence() {
        let visible = panel?.isVisible ?? false
        if visible, !hasDockPresence {
            ActivationPolicyKeeper.retain("ai.aggregated")
            hasDockPresence = true
        } else if !visible, hasDockPresence {
            ActivationPolicyKeeper.release("ai.aggregated")
            hasDockPresence = false
        }
    }

    /// 刷新当前活跃标签的页面
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

    // MARK: - 窗口构造

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

    /// 确保聚合窗口已创建
    private func ensureWindow() {
        guard panel == nil else { return }

        let newPanel = AIWebViewPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: defaultWidth, height: defaultHeight)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
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
            self?.saveWindowFrame()
            self?.panel?.orderOut(nil)
            self?.syncDockPresence()
        }

        // 恢复上次的窗口位置和大小
        restoreWindowFrame(newPanel)

        // 内容布局：标签栏 + WebView 容器 + 悬浮胶囊
        let hostView = NSView(frame: newPanel.contentView?.bounds ?? .zero)
        hostView.autoresizingMask = [.width, .height]

        // 标签栏
        let tabBar = AITabBarView(onSelect: { [weak self] id in
            self?.switchToTab(id)
        }, onClose: { [weak self] id in
            self?.destroyWindow(for: id)
        })
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(tabBar)

        // WebView 容器
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(container)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: hostView.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: DesignTokens.Size.aiTabBarHeight),

            container.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
        ])

        // 悬浮胶囊叠在 WebView 容器上
        let capsuleView = FloatingCapsuleView(
            positionKey: "ai.aggregated",
            actions: [
                CapsuleAction(
                    id: Self.pinActionID,
                    symbol: "pin",
                    tooltip: "窗口置顶",
                    kind: .toggle
                ) { [weak self] in
                    self?.toggleAlwaysOnTop()
                },
                CapsuleAction(
                    id: "reload",
                    symbol: "arrow.clockwise",
                    tooltip: "刷新当前页面"
                ) { [weak self] in
                    guard let activeID = self?.activeProviderID else { return }
                    self?.reloadWindow(for: activeID)
                },
                CapsuleAction(
                    id: "external",
                    symbol: "arrow.up.right.square",
                    tooltip: "在浏览器中打开"
                ) { [weak self] in
                    guard let activeID = self?.activeProviderID else { return }
                    self?.openInBrowser(providerId: activeID)
                },
                CapsuleAction(
                    id: "close",
                    symbol: "xmark",
                    tooltip: "关闭当前标签",
                    kind: .destructive
                ) { [weak self] in
                    guard let activeID = self?.activeProviderID else { return }
                    self?.destroyWindow(for: activeID)
                }
            ])
        hostView.addSubview(capsuleView)
        capsuleView.positionInSuperview()

        newPanel.contentView = hostView

        // 窗口默认置顶
        if PluginDefaults.isEnabled(PluginSettingKey.AIPortal.defaultAlwaysOnTop, default: false) {
            newPanel.level = .floating
            capsuleView.setToggle(Self.pinActionID, isOn: true, tooltip: "取消置顶")
        }

        panel = newPanel
        tabBarView = tabBar
        contentContainer = container
        capsule = capsuleView

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
        tabBarView?.addTab(id: provider.id, title: provider.name, icon: provider.icon)
    }

    /// 切换到指定标签页
    private func switchToTab(_ providerId: String) {
        guard let container = contentContainer,
            let webView = webViews[providerId]
        else { return }

        // 移除当前 WebView
        container.subviews.forEach { $0.removeFromSuperview() }

        // 添加新的 WebView
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)

        activeProviderID = providerId
        tabBarView?.selectTab(providerId)

        // 更新窗口标题
        if let provider = AIProviderRegistry.provider(for: providerId) {
            panel?.title = provider.name
        }
    }

    // MARK: - 窗口置顶

    func toggleAlwaysOnTop() {
        guard let panel else { return }
        let newState = panel.level != .floating
        panel.level = newState ? .floating : .normal
        capsule?.setToggle(
            Self.pinActionID,
            isOn: newState,
            tooltip: newState ? "取消置顶" : "窗口置顶"
        )
    }

    /// 设置窗口置顶状态
    func setAlwaysOnTop(for _: String, flag: Bool) {
        guard let panel else { return }
        panel.level = flag ? .floating : .normal
        capsule?.setToggle(
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

    /// 获取所有已打开标签的 Provider ID
    func activeProviderIDs() -> Set<String> {
        guard let panel, panel.isVisible else { return [] }
        return Set(webViews.keys)
    }

    // MARK: - 窗口位置持久化

    private func saveWindowFrame() {
        guard let panel else { return }
        let frame = panel.frame
        UserDefaults.standard.set(
            ["x": frame.origin.x, "y": frame.origin.y,
             "w": frame.size.width, "h": frame.size.height],
            forKey: Self.frameKey
        )
    }

    private func restoreWindowFrame(_ panel: AIWebViewPanel) {
        if let saved = UserDefaults.standard.dictionary(forKey: Self.frameKey),
            let x = saved["x"] as? CGFloat,
            let y = saved["y"] as? CGFloat,
            let w = saved["w"] as? CGFloat,
            let h = saved["h"] as? CGFloat
        {
            let frame = NSRect(x: x, y: y, width: max(w, 600), height: max(h, 400))
            // 确保窗口在可见屏幕范围内
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                panel.setFrame(frame, display: false)
                return
            }
        }
        panel.center()
    }
}

// MARK: - 标签栏视图

/// AI 聚合窗口的标签栏
///
/// 每个打开的 Provider 一个标签项，支持点击切换和关闭
@MainActor
final class AITabBarView: NSView {

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
        wantsLayer = true
        layer?.backgroundColor = NSColor(DesignTokens.Colors.aiTabBarBackground).cgColor

        // 底部分隔线
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(DesignTokens.Colors.aiTabSeparator).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

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
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.sm),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Spacing.sm),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
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
        layer?.backgroundColor = NSColor(DesignTokens.Colors.aiTabBarBackground).cgColor
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
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
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

            widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            heightAnchor.constraint(equalToConstant: DesignTokens.Size.aiTabBarHeight - 4)
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
