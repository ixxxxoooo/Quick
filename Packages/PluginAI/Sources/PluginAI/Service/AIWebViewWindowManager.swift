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

        if isMergeMode || mergedPanel != nil {
            return openOrFocusMerged(provider: provider)
        } else {
            return openOrFocusSeparate(provider: provider)
        }
    }

    /// 检查指定 Provider 窗口是否打开
    func isWindowOpen(for providerId: String) -> Bool {
        if isMergeMode || mergedPanel != nil {
            guard let panel = mergedPanel, panel.isVisible else { return false }
            return activeProviderID == providerId
        } else {
            return separateWindows[providerId]?.panel.isVisible ?? false
        }
    }

    /// 检查聚合窗口是否打开且可见
    func isMergedWindowOpen() -> Bool {
        mergedPanel?.isVisible ?? false
    }

    /// 切换 Provider 窗口显隐
    @discardableResult
    func toggle(providerId: String) -> Bool {
        if isMergeMode || mergedPanel != nil {
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

    /// 切换聚合窗口显隐
    @discardableResult
    func toggleMergedWindow() -> Bool {
        if let panel = mergedPanel, panel.isVisible {
            saveMergedFrame()
            saveTabState()
            panel.orderOut(nil)
            syncDockPresence()
            log.notice("切换：隐藏聚合窗口")
            return false
        }
        return openOrFocusMergedWindow()
    }

    /// 隐藏窗口
    func hideWindow(for providerId: String) {
        if isMergeMode || mergedPanel != nil {
            saveMergedFrame()
            saveTabState()
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

        if isMergeMode || mergedPanel != nil {
            titleTabBar?.removeTab(providerId)
            saveOpenTabs()
            if activeProviderID == providerId {
                let remaining = (titleTabBar?.tabIDs ?? []).filter {
                    Self.isProviderEnabled($0) && webViews[$0] != nil
                }
                if let next = remaining.first {
                    switchToTab(next)
                } else {
                    activeProviderID = nil
                    titleTabBar?.selectTab(nil)
                    mergedPanel?.orderOut(nil)
                    UserDefaults.standard.removeObject(forKey: PluginSettingKey.AIPortal.lastActiveTab)
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
        saveTabState()
        for (id, webView) in webViews {
            webView.stopLoading()
            log.notice("关闭: \(id, privacy: .public)")
        }
        webViews.removeAll()
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
        let anyVisible = (mergedPanel?.isVisible ?? false) || separateWindows.values.contains { $0.panel.isVisible }
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
        var ids = Set<String>()
        if let panel = mergedPanel, panel.isVisible {
            ids.formUnion(webViews.keys)
        }
        ids.formUnion(separateWindows.filter { $0.value.panel.isVisible }.map(\.key))
        return ids
    }

    /// 标准 macOS Safari User-Agent（避免 Kimi 等使用 Lexical 富文本编辑器的站点将 WebKit 误判为 Chrome/Blink 内核而拦截输入）
    static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"

    // MARK: - 独立窗口模式

    private func openOrFocusSeparate(provider: AIProvider) -> Bool {
        ensureWebView(for: provider)

        if let win = separateWindows[provider.id] {
            EventBus.shared.post(HidePaletteEvent(restoreFocus: false))
            win.panel.makeKeyAndOrderFront(nil)
            win.panel.orderFrontRegardless()
            syncDockPresence()
            NSApp.activate(ignoringOtherApps: true)
            win.panel.makeFirstResponder(win.webView)
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
        panel.isMovableByWindowBackground = false
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

        EventBus.shared.post(HidePaletteEvent(restoreFocus: false))
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        syncDockPresence()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(webView)
        log.notice("打开独立窗口: \(provider.name, privacy: .public)")
        return true
    }

    // MARK: - 聚合窗口模式

    private func openOrFocusMerged(provider: AIProvider) -> Bool {
        ensureMergedWindow()
        restoreSavedTabsIfNeeded()
        ensureWebView(for: provider)
        switchToTab(provider.id)

        guard let panel = mergedPanel else { return false }

        EventBus.shared.post(HidePaletteEvent(restoreFocus: false))
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        syncDockPresence()
        NSApp.activate(ignoringOtherApps: true)
        if let webView = webViews[provider.id] {
            panel.makeFirstResponder(webView)
        }
        log.notice("聚焦标签: \(provider.name, privacy: .public)")
        return true
    }

    /// 打开或聚焦聚合窗口，保持当前/上次选中的标签页状态
    @discardableResult
    func openOrFocusMergedWindow() -> Bool {
        ensureMergedWindow()
        restoreSavedTabsIfNeeded()

        guard let panel = mergedPanel else { return false }

        if let activeID = activeProviderID, webViews[activeID] != nil {
            switchToTab(activeID)
        } else if let firstTab = titleTabBar?.tabIDs.first, webViews[firstTab] != nil {
            switchToTab(firstTab)
        }

        EventBus.shared.post(HidePaletteEvent(restoreFocus: false))
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        syncDockPresence()
        NSApp.activate(ignoringOtherApps: true)
        if let activeID = activeProviderID, let webView = webViews[activeID] {
            panel.makeFirstResponder(webView)
        }
        log.notice("聚焦聚合窗口: 当前标签 \(self.activeProviderID ?? "无", privacy: .public)")
        return true
    }

    /// 确保聚合窗口已创建（标签栏嵌入标题栏，内容区在标题栏下方，互不重叠）
    private func ensureMergedWindow() {
        guard mergedPanel == nil else { return }

        // 不使用 fullSizeContentView：内容区域自然在标题栏下方，不会重叠
        let newPanel = AIWebViewPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: defaultWidth, height: defaultHeight)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newPanel.title = "AI 聚合"
        // 标题栏保持不透明，标签嵌在里面；隐藏系统标题文字
        newPanel.titlebarAppearsTransparent = false
        newPanel.titleVisibility = .hidden
        newPanel.isMovableByWindowBackground = false
        newPanel.minSize = NSSize(width: 600, height: 400)
        newPanel.isReleasedWhenClosed = false
        newPanel.hidesOnDeactivate = false
        newPanel.identifier = NSUserInterfaceItemIdentifier("quick.ai.aggregated")

        newPanel.onClose = { [weak self] in
            self?.saveMergedFrame()
            self?.saveTabState()
            self?.mergedPanel?.orderOut(nil)
            self?.syncDockPresence()
        }

        restoreMergedFrame(newPanel)

        // 标签栏嵌入标题栏内部（与红绿灯同行）
        let tabBar = AITitleTabBarView(
            onSelect: { [weak self] id in
                self?.switchToTab(id)
            },
            onClose: { [weak self] id in
                self?.destroyWindow(for: id)
            },
            onAddProvider: { [weak self] id in
                guard let self else { return }
                guard let provider = AIProviderRegistry.provider(for: id),
                    Self.isProviderEnabled(id)
                else { return }
                _ = self.openOrFocusMerged(provider: provider)
            },
            onTogglePin: { [weak self] in
                self?.toggleAlwaysOnTop(forMerged: true)
            },
            onReload: { [weak self] in
                guard let id = self?.activeProviderID else { return }
                self?.reloadWindow(for: id)
            },
            onOpenExternal: { [weak self] in
                guard let id = self?.activeProviderID else { return }
                self?.openInBrowser(providerId: id)
            },
            onCloseActive: { [weak self] in
                guard let id = self?.activeProviderID else { return }
                self?.destroyWindow(for: id)
            }
        )
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        // 找到标题栏容器并将标签栏加入
        if let titlebarContainer = newPanel.standardWindowButton(.closeButton)?.superview?.superview {
            titlebarContainer.addSubview(tabBar)
            NSLayoutConstraint.activate([
                tabBar.leadingAnchor.constraint(
                    equalTo: titlebarContainer.leadingAnchor,
                    constant: DesignTokens.Size.aiTitleBarTabLeading),
                tabBar.trailingAnchor.constraint(equalTo: titlebarContainer.trailingAnchor),
                tabBar.topAnchor.constraint(equalTo: titlebarContainer.topAnchor),
                tabBar.bottomAnchor.constraint(equalTo: titlebarContainer.bottomAnchor),
            ])
        }

        // 内容区域：不用 fullSizeContentView，contentView 自然在标题栏下方
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

        if PluginDefaults.isEnabled(PluginSettingKey.AIPortal.defaultAlwaysOnTop, default: false) {
            newPanel.level = .floating
            tabBar.setPinned(true)
        }

        newPanel.contentView = hostView

        mergedPanel = newPanel
        titleTabBar = tabBar
        contentContainer = container

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
        webView.customUserAgent = Self.safariUserAgent

        if let url = URL(string: provider.url) {
            webView.load(URLRequest(url: url))
        }

        webViews[provider.id] = webView

        if isMergeMode || mergedPanel != nil {
            titleTabBar?.addTab(id: provider.id, title: provider.name, icon: provider.icon)
            saveOpenTabs()
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
        mergedPanel?.makeFirstResponder(webView)

        activeProviderID = providerId
        titleTabBar?.selectTab(providerId)

        if let provider = AIProviderRegistry.provider(for: providerId) {
            mergedPanel?.title = provider.name
        }

        UserDefaults.standard.set(providerId, forKey: PluginSettingKey.AIPortal.lastActiveTab)
        saveOpenTabs()
    }

    // MARK: - 标签页状态持久化

    private func saveTabState() {
        if let active = activeProviderID {
            UserDefaults.standard.set(active, forKey: PluginSettingKey.AIPortal.lastActiveTab)
        }
        saveOpenTabs()
    }

    private func saveOpenTabs() {
        let tabs = titleTabBar?.tabIDs ?? Array(webViews.keys)
        UserDefaults.standard.set(tabs, forKey: PluginSettingKey.AIPortal.openTabs)
    }

    private func restoreSavedTabsIfNeeded() {
        if let bar = titleTabBar, bar.tabCount > 0 {
            return
        }

        var savedTabs = UserDefaults.standard.stringArray(forKey: PluginSettingKey.AIPortal.openTabs) ?? []
        savedTabs = savedTabs.filter { id in
            AIProviderRegistry.provider(for: id) != nil && Self.isProviderEnabled(id)
        }

        let savedActive = UserDefaults.standard.string(forKey: PluginSettingKey.AIPortal.lastActiveTab)
        let validSavedActive: String? = {
            guard let id = savedActive,
                AIProviderRegistry.provider(for: id) != nil,
                Self.isProviderEnabled(id)
            else { return nil }
            return id
        }()

        if let active = validSavedActive, !savedTabs.contains(active) {
            savedTabs.append(active)
        }

        if savedTabs.isEmpty {
            if let firstEnabled = AIProviderRegistry.all.first(where: { Self.isProviderEnabled($0.id) }) {
                savedTabs.append(firstEnabled.id)
            }
        }

        for id in savedTabs {
            if let provider = AIProviderRegistry.provider(for: id) {
                ensureWebView(for: provider)
            }
        }

        let targetTab = (validSavedActive != nil && savedTabs.contains(validSavedActive!))
            ? validSavedActive!
            : (savedTabs.first ?? "")

        if !targetTab.isEmpty {
            switchToTab(targetTab)
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
            titleTabBar?.setPinned(newState)
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
            titleTabBar?.setPinned(flag)
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
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: 600, height: 400)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.identifier = NSUserInterfaceItemIdentifier("quick.ai.\(provider.id)")
        return panel
    }
}

// MARK: - 标题栏图标按钮

/// 标题栏图标按钮（用于新建标签加号与右侧常驻操作按钮）
@MainActor
final class AITitleBarIconButton: NSButton {

    private var isHovered = false
    private var isActive = false
    private let baseSymbol: String
    private let activeSymbol: String?
    private var onAction: (() -> Void)?

    override var isFlipped: Bool { true }

    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1.0 : 0.4
        }
    }

    init(
        symbol: String,
        activeSymbol: String? = nil,
        tooltip: String,
        action: @escaping () -> Void
    ) {
        self.baseSymbol = symbol
        self.activeSymbol = activeSymbol
        self.onAction = action
        super.init(frame: .zero)

        self.toolTip = tooltip
        self.isBordered = false
        self.imagePosition = .imageOnly
        self.imageScaling = .scaleProportionallyDown
        self.target = self
        self.action = #selector(handleClick)

        wantsLayer = true
        layer?.cornerRadius = DesignTokens.Size.aiTitleBarTabHeight / 2

        updateIcon()
        translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: DesignTokens.Size.aiTitleBarTabHeight),
            heightAnchor.constraint(equalToConstant: DesignTokens.Size.aiTitleBarTabHeight),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    @objc func handleClick() {
        onAction?()
    }

    override func performClick(_ sender: Any?) {
        handleClick()
    }

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        updateIcon()
        refreshAppearance()
    }

    private func updateIcon() {
        let sym = (isActive ? activeSymbol : nil) ?? baseSymbol
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        image = NSImage(systemSymbolName: sym, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(config)
        imageScaling = .scaleProportionallyDown
        refreshAppearance()
    }

    private func refreshAppearance() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.Duration.hover
            context.allowsImplicitAnimation = true
            if isActive {
                let baseColor = NSColor(DesignTokens.Colors.capsuleToggleFill)
                layer?.backgroundColor = isHovered
                    ? baseColor.withAlphaComponent(min(baseColor.alphaComponent + 0.10, 1.0)).cgColor
                    : baseColor.cgColor
                contentTintColor = NSColor(DesignTokens.Colors.capsuleToggleGlyph)
            } else if isHovered {
                layer?.backgroundColor = NSColor(DesignTokens.Colors.aiTabSelected).cgColor
                contentTintColor = NSColor(DesignTokens.Colors.aiTabSelectedText)
            } else {
                layer?.backgroundColor = nil
                contentTintColor = NSColor(DesignTokens.Colors.aiTabText)
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with _: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
        refreshAppearance()
    }

    override func mouseExited(with _: NSEvent) {
        isHovered = false
        refreshAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
}

// MARK: - 标题栏标签视图

/// 嵌入标题栏的标签栏，用于聚合模式
///
/// 每个打开的 Provider 一个标签项，支持点击切换和关闭；
/// 标签栏右侧提供加号弹出菜单快速打开/跳转各个 AI 官网，
/// 最右侧固定放置置顶、刷新、外部浏览器打开、关闭标签等窗口操作按钮。
@MainActor
final class AITitleTabBarView: NSView {

    private let onSelect: (String) -> Void
    private let onClose: (String) -> Void
    private let onAddProvider: (String) -> Void
    private let onTogglePin: () -> Void
    private let onReload: () -> Void
    private let onOpenExternal: () -> Void
    private let onCloseActive: () -> Void

    let scrollView = NSScrollView()
    let stackView = NSStackView()
    let actionsStackView = NSStackView()
    private var tabs: [(id: String, view: AITabItemView)] = []
    var tabCount: Int { tabs.count }
    var tabIDs: [String] { tabs.map(\.id) }
    private(set) var selectedID: String?

    override var mouseDownCanMoveWindow: Bool { true }

    lazy var addButton: AITitleBarIconButton = {
        AITitleBarIconButton(
            symbol: "plus",
            tooltip: "打开 AI 入口",
            action: { [weak self] in self?.showAddMenu() }
        )
    }()

    lazy var pinButton: AITitleBarIconButton = {
        AITitleBarIconButton(
            symbol: "pin",
            activeSymbol: "pin.fill",
            tooltip: "窗口置顶",
            action: { [weak self] in self?.onTogglePin() }
        )
    }()

    lazy var reloadButton: AITitleBarIconButton = {
        AITitleBarIconButton(
            symbol: "arrow.clockwise",
            tooltip: "刷新当前页面",
            action: { [weak self] in self?.onReload() }
        )
    }()

    lazy var externalButton: AITitleBarIconButton = {
        AITitleBarIconButton(
            symbol: "arrow.up.right.square",
            tooltip: "在浏览器中打开",
            action: { [weak self] in self?.onOpenExternal() }
        )
    }()

    lazy var closeButton: AITitleBarIconButton = {
        AITitleBarIconButton(
            symbol: "xmark",
            tooltip: "关闭当前标签",
            action: { [weak self] in self?.onCloseActive() }
        )
    }()

    init(
        onSelect: @escaping (String) -> Void,
        onClose: @escaping (String) -> Void,
        onAddProvider: @escaping (String) -> Void,
        onTogglePin: @escaping () -> Void,
        onReload: @escaping () -> Void,
        onOpenExternal: @escaping () -> Void,
        onCloseActive: @escaping () -> Void
    ) {
        self.onSelect = onSelect
        self.onClose = onClose
        self.onAddProvider = onAddProvider
        self.onTogglePin = onTogglePin
        self.onReload = onReload
        self.onOpenExternal = onOpenExternal
        self.onCloseActive = onCloseActive
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    private func setupViews() {
        // 1. 标签区 StackView（标签项 + 加号按钮）
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = DesignTokens.Size.aiTabItemSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(addButton)

        scrollView.documentView = stackView
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        // 2. 右侧操作区 StackView
        actionsStackView.orientation = .horizontal
        actionsStackView.alignment = .centerY
        actionsStackView.spacing = DesignTokens.Size.aiTabItemSpacing
        actionsStackView.translatesAutoresizingMaskIntoConstraints = false

        actionsStackView.addArrangedSubview(pinButton)
        actionsStackView.addArrangedSubview(reloadButton)
        actionsStackView.addArrangedSubview(externalButton)
        actionsStackView.addArrangedSubview(closeButton)
        addSubview(actionsStackView)

        let scrollWidth = scrollView.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        scrollWidth.priority = .defaultLow

        NSLayoutConstraint.activate([
            // 右侧固定操作区
            actionsStackView.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -DesignTokens.Spacing.lg),
            actionsStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionsStackView.heightAnchor.constraint(
                equalToConstant: DesignTokens.Size.aiTitleBarTabHeight),

            // 左侧可滚动标签区（最多延伸到操作区左侧）
            scrollView.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: DesignTokens.Spacing.xs),
            scrollView.trailingAnchor.constraint(
                lessThanOrEqualTo: actionsStackView.leadingAnchor,
                constant: -DesignTokens.Spacing.sm),
            scrollWidth,
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
        let insertIndex = max(0, stackView.arrangedSubviews.count - 1)
        stackView.insertArrangedSubview(tab, at: insertIndex)
    }

    func removeTab(_ id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index].view
        stackView.removeArrangedSubview(tab)
        tab.removeFromSuperview()
        tabs.remove(at: index)
    }

    func selectTab(_ id: String?) {
        selectedID = id
        for (tabID, view) in tabs {
            let isCurrent = (tabID == id)
            view.setSelected(isCurrent)
            if isCurrent {
                view.scrollToVisible(view.bounds)
            }
        }
        let hasActive = (id != nil)
        reloadButton.isEnabled = hasActive
        externalButton.isEnabled = hasActive
        closeButton.isEnabled = hasActive
    }

    func setPinned(_ isPinned: Bool) {
        pinButton.setActive(isPinned)
        pinButton.toolTip = isPinned ? "取消置顶" : "窗口置顶"
    }

    private func showAddMenu() {
        let menu = NSMenu()
        let enabledProviders = AIProviderRegistry.all.filter {
            AIWebViewWindowManager.isProviderEnabled($0.id)
        }
        for provider in enabledProviders {
            let item = NSMenuItem(
                title: provider.name,
                action: #selector(handleProviderMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = provider.id
            if let img = NSImage(
                systemSymbolName: provider.icon, accessibilityDescription: provider.name)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
            {
                item.image = img
            }
            if provider.id == selectedID {
                item.state = .on
            }
            menu.addItem(item)
        }

        let point = NSPoint(x: 0, y: addButton.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: addButton)
    }

    @objc private func handleProviderMenuItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onAddProvider(id)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        for tab in tabs {
            tab.view.viewDidChangeEffectiveAppearance()
        }
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
        // 半高圆角 → 药丸形，比固定值更适配标题栏
        layer?.cornerRadius = DesignTokens.Size.aiTitleBarTabHeight / 2

        let iconSize = DesignTokens.Size.aiTabIconSize
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: iconSize - 2, weight: .medium))
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

        let closeSize = DesignTokens.Size.aiTabCloseSize
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭标签")?
            .withSymbolConfiguration(.init(pointSize: closeSize - 4, weight: .medium))
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

        let padding = DesignTokens.Size.aiTabItemPaddingH
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -2),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding + 2),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: closeSize),
            closeButton.heightAnchor.constraint(equalToConstant: closeSize),

            widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            widthAnchor.constraint(lessThanOrEqualToConstant: 150),
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
