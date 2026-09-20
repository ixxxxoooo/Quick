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

    /// 刷新页面
    func reloadWindow(for providerId: String) {
        guard let window = windows[providerId] else { return }
        if let url = AIProviderRegistry.provider(for: providerId).map({ URL(string: $0.url) }) ?? nil {
            window.webView.load(URLRequest(url: url))
        } else {
            window.webView.reload()
        }
    }

    /// 切换窗口置顶
    func toggleAlwaysOnTop(for providerId: String) {
        guard let window = windows[providerId] else { return }
        let isFloating = window.panel.level == .floating
        let newLevel: NSWindow.Level = isFloating ? .normal : .floating
        window.panel.level = newLevel
        window.capsule?.updatePinState(isPinned: !isFloating)
    }

    /// 设置窗口置顶状态
    func setAlwaysOnTop(for providerId: String, flag: Bool) {
        guard let window = windows[providerId] else { return }
        window.panel.level = flag ? .floating : .normal
        window.capsule?.updatePinState(isPinned: flag)
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

        let providerId = provider.id
        panel.onClose = { [weak panel] in
            panel?.orderOut(nil)
        }

        // 内容视图布局：WebView 填充 + 悬浮胶囊叠加
        let hostView = NSView(frame: panel.contentView?.bounds ?? .zero)
        hostView.autoresizingMask = [.width, .height]
        webView.frame = hostView.bounds
        webView.autoresizingMask = [.width, .height]
        hostView.addSubview(webView)

        // 悬浮胶囊（原生 NSView，不依赖网页 DOM）
        let capsule = AICapsuleView(
            providerId: providerId,
            onPin: { [weak self] in self?.toggleAlwaysOnTop(for: providerId) },
            onReload: { [weak self] in self?.reloadWindow(for: providerId) },
            onExternal: { [weak self] in self?.openInBrowser(providerId: providerId) },
            onClose: { [weak self] in self?.destroyWindow(for: providerId) }
        )
        hostView.addSubview(capsule)
        capsule.positionInSuperview()

        panel.contentView = hostView

        return AIWebViewWindow(panel: panel, webView: webView, providerId: provider.id, capsule: capsule)
    }
}

// MARK: - 窗口数据

struct AIWebViewWindow {
    let panel: AIWebViewPanel
    let webView: WKWebView
    let providerId: String
    let capsule: AICapsuleView?
}

/// 自定义 NSPanel，关闭时隐藏
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

// MARK: - 悬浮胶囊视图

/// AI 窗口内悬浮操作胶囊
///
/// 参考 Fasty capsuleInjectionScript 的交互设计：
/// - 默认收起状态仅显示一个小抓手图标
/// - 点击展开后显示：置顶 / 刷新 / 外部浏览器 / 关闭
/// - 可拖拽定位（位置持久化到 UserDefaults）
/// - 适配明暗主题
final class AICapsuleView: NSView {

    private let providerId: String
    private let onPin: () -> Void
    private let onReload: () -> Void
    private let onExternal: () -> Void
    private let onClose: () -> Void

    private var isCollapsed = true
    private var isPinned = false
    private var isDragging = false
    private var dragStart: NSPoint = .zero
    private var frameStart: NSPoint = .zero

    private var pinButton: NSButton!
    private var reloadButton: NSButton!
    private var externalButton: NSButton!
    private var closeButton: NSButton!
    private var toggleButton: NSButton!
    private var actionsStack: NSStackView!

    private let posKey: String

    init(
        providerId: String,
        onPin: @escaping () -> Void,
        onReload: @escaping () -> Void,
        onExternal: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.providerId = providerId
        self.onPin = onPin
        self.onReload = onReload
        self.onExternal = onExternal
        self.onClose = onClose
        self.posKey = "ai.capsule.pos.\(providerId)"
        super.init(frame: .zero)
        setupViews()
        updateCollapsedState()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    // MARK: - 布局

    func positionInSuperview() {
        guard let superview else { return }
        // 恢复保存的位置，或默认右上角
        if let data = UserDefaults.standard.data(forKey: posKey),
            let point = try? JSONDecoder().decode(CGPoint.self, from: data)
        {
            frame.origin = CGPoint(
                x: min(max(4, point.x), superview.bounds.width - frame.width - 4),
                y: min(max(4, point.y), superview.bounds.height - frame.height - 4)
            )
        } else {
            frame.origin = CGPoint(
                x: superview.bounds.width - frame.width - 14,
                y: superview.bounds.height - frame.height - 10
            )
        }
        autoresizingMask = [.minXMargin, .minYMargin]
    }

    func updatePinState(isPinned: Bool) {
        self.isPinned = isPinned
        pinButton.contentTintColor = isPinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.toolTip = isPinned ? "取消置顶" : "窗口置顶"
    }

    // MARK: - 视图构建

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.15)
        shadow?.shadowBlurRadius = 8
        shadow?.shadowOffset = NSSize(width: 0, height: -2)

        // 功能按钮
        pinButton = makeButton(symbol: "pin", tooltip: "窗口置顶", action: #selector(pinTapped))
        reloadButton = makeButton(symbol: "arrow.clockwise", tooltip: "刷新页面", action: #selector(reloadTapped))
        externalButton = makeButton(
            symbol: "arrow.up.right.square", tooltip: "在浏览器中打开", action: #selector(externalTapped))
        closeButton = makeButton(symbol: "xmark", tooltip: "关闭窗口", action: #selector(closeTapped))
        closeButton.contentTintColor = .systemRed

        actionsStack = NSStackView(views: [pinButton, reloadButton, externalButton, closeButton])
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 2
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionsStack)

        // 展开/收起按钮
        toggleButton = makeButton(
            symbol: "chevron.right", tooltip: "展开工具栏", action: #selector(toggleTapped))
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggleButton)

        NSLayoutConstraint.activate([
            actionsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            actionsStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggleButton.leadingAnchor.constraint(equalTo: actionsStack.trailingAnchor, constant: 0),
            toggleButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            toggleButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        frame.size = NSSize(width: 28, height: 28)
    }

    private func makeButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        btn.imageScaling = .scaleProportionallyDown
        btn.isBordered = false
        btn.bezelStyle = .accessoryBarAction
        btn.toolTip = tooltip
        btn.target = self
        btn.action = action
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 22),
            btn.heightAnchor.constraint(equalToConstant: 22)
        ])
        btn.contentTintColor = .secondaryLabelColor
        return btn
    }

    // MARK: - 收起/展开

    private func updateCollapsedState() {
        actionsStack.isHidden = isCollapsed
        let symbol = isCollapsed ? "chevron.left" : "chevron.right"
        toggleButton.image = NSImage(
            systemSymbolName: symbol, accessibilityDescription: isCollapsed ? "展开" : "收起")
        let w: CGFloat = isCollapsed ? 28 : (4 + CGFloat(4) * 24 + CGFloat(3) * 2 + 22 + 2)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            self.frame.size.width = w
            self.superview?.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - 按钮事件

    @objc private func pinTapped() { onPin() }
    @objc private func reloadTapped() { onReload() }
    @objc private func externalTapped() { onExternal() }
    @objc private func closeTapped() { onClose() }

    @objc private func toggleTapped() {
        isCollapsed.toggle()
        updateCollapsedState()
    }

    // MARK: - 拖拽

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        frameStart = frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let current = event.locationInWindow
        let dx = current.x - dragStart.x
        let dy = current.y - dragStart.y
        if !isDragging && (abs(dx) > 3 || abs(dy) > 3) {
            isDragging = true
        }
        guard isDragging, let sv = superview else { return }
        let x = min(sv.bounds.width - frame.width - 4, max(4, frameStart.x + dx))
        let y = min(sv.bounds.height - frame.height - 4, max(4, frameStart.y + dy))
        frame.origin = CGPoint(x: x, y: y)
    }

    override func mouseUp(with _: NSEvent) {
        if isDragging {
            // 持久化位置
            if let data = try? JSONEncoder().encode(frame.origin) {
                UserDefaults.standard.set(data, forKey: posKey)
            }
        }
        isDragging = false
    }

    // MARK: - 外观

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override var wantsUpdateLayer: Bool { true }
}

// MARK: - CGPoint Codable

extension CGPoint: @retroactive Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}

extension CGPoint: @retroactive Decodable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(CGFloat.self)
        let y = try container.decode(CGFloat.self)
        self.init(x: x, y: y)
    }
}
