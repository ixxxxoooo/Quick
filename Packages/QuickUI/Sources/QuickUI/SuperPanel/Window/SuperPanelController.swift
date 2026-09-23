// SuperPanelController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 超级面板的宿主组件
///
/// 与 `PaletteCoordinator` 平级：它拥有一个独立浮窗，在鼠标处弹出，识别选区/剪贴板后
/// 给出即时动作或工作台。它**不是插件** —— 不进主面板搜索、不进插件列表，设置也自成一处。
///
/// 系统能力（抓选区、合成粘贴、最近使用解析）由 `AppCore` 注入：`QuickUI` 不认识
/// `QuickPlatform`，也不认识插件，依赖方向保持单向。
@MainActor
public final class SuperPanelController {

    /// 状态容器（供 SwiftUI 观察）
    public let model = SuperPanelModel()

    /// 是否可见
    public var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - 宿主注入的能力

    /// 抓当前选区文本（合成 ⌘C）。可能返回 nil（无权限 / 无选区）
    public var captureSelection: (@Sendable () -> String?)?
    /// 是否具备合成粘贴的能力（辅助功能权限）
    public var canPaste: (() -> Bool)?
    /// 合成一次 ⌘V
    public var paste: (() -> Void)?
    /// 最近使用条目（由宿主从 `UsageHistory` 解析）
    public var recentItems: (() -> [SuperPanelRecentItem])?
    /// 打开设置窗口并定位到超级面板页
    public var openSettings: (() -> Void)?

    // MARK: - 内部状态

    private let log = QuickLog.ui
    private var panel: SuperPanelPanel?
    private var placement: SuperPanelPlacement?
    private var targetVisibleFrame: CGRect?
    /// 面板出现前的前台应用（替换原文 / 跳转插件时交还焦点）
    private var previousApp: NSRunningApplication?
    /// 出现时刻，用于失焦保护
    private var shownAt: Date?
    private var outsideClickMonitor: Any?
    private var outsideClickLocalMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var toastTask: Task<Void, Never>?

    /// 是否已经把面板显示出来（alpha 0 → 1）
    ///
    /// 唤出时先把窗口摆好、量好内容高度，再一次性显形 —— 否则用户会看到面板先以
    /// 「加载中」的矮高度出现，再撑到内容高度，像一段展开动画。
    private var isRevealed = false
    /// 内容是否已经加载完成（可以显形了）
    private var contentReady = false
    /// 兜底显形：内容高度没变化时 `onPreferenceChange` 不会回调，靠它把面板显示出来
    private var revealFallback: Task<Void, Never>?

    /// 唤出代数：抓选区是异步的，期间又唤出一次时用它丢弃过期结果
    private var showGeneration = 0

    /// 失焦保护期：刚出现的一瞬间，底层窗口松手 / 焦点切换会触发失焦，不能立刻收起
    private static let focusProtection: TimeInterval = 0.35
    /// 交还焦点后合成 ⌘V 的等待
    private static let pasteSettleDelay = Duration.milliseconds(160)

    public init() {}

    /// 预热：提前把窗口与根视图建好，避免首次唤出时的白屏与延迟（对齐 Fasty 的预热）
    public func prewarm() {
        ensurePanel()
    }

    // MARK: - 显隐

    /// 切换显隐
    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// 在鼠标处弹出
    public func show() {
        let cursor = NSEvent.mouseLocation
        let screen = ScreenPlacement.screen(under: cursor) ?? NSScreen.main
        guard let screen else {
            log.warning("超级面板唤出失败：找不到可用屏幕")
            return
        }

        previousApp = NSWorkspace.shared.frontmostApplication
        model.prepareForPresentation()

        let visibleFrame = screen.visibleFrame
        targetVisibleFrame = visibleFrame
        let initialSize = CGSize(
            width: SuperPanelMetrics.width, height: SuperPanelMetrics.initialHeight)
        let placement = SuperPanelPlacement.resolve(
            cursor: cursor, panelSize: initialSize, visibleFrame: visibleFrame)
        self.placement = placement

        ensurePanel()
        guard let panel else { return }
        // 先以透明摆好：窗口要真正在屏上布局过，根视图才会量出内容高度。
        // 量好、显形之前用户看不到任何中间态。
        showGeneration += 1
        let generation = showGeneration
        isRevealed = false
        contentReady = false
        revealFallback?.cancel()
        revealFallback = nil
        panel.alphaValue = 0
        panel.setContentSize(initialSize)
        panel.setFrameOrigin(placement.origin(for: initialSize, visibleFrame: visibleFrame))

        log.notice(
            "超级面板已唤出，光标=(\(Int(cursor.x), privacy: .public), \(Int(cursor.y), privacy: .public))，方向=\(String(describing: placement.horizontal), privacy: .public)/\(String(describing: placement.vertical), privacy: .public)"
        )

        // **抓选区必须在面板取得焦点之前。** 抓选区是合成 ⌘C：一旦面板 `makeKey` +
        // `NSApp.activate` 把焦点抢过来，⌘C 就打在了 Quick 自己身上，原应用里那段
        // 鼠标选中的文字根本收不到 —— 结果只能退回去读剪贴板（没复制就什么都没有）。
        // 所以先抓、抓完再显示，与 Fasty 的顺序一致。
        let capture = captureSelection
        Task.detached(priority: .userInitiated) {
            let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
            let selected = capture?()
            let source = (selected?.isEmpty == false ? selected : nil) ?? clipboard
            let previews = SmartPreviewDetector.detect(source)
            await MainActor.run { [weak self, weak panel] in
                guard let self, let panel, self.showGeneration == generation else { return }
                self.presentPanel(panel)
                self.shownAt = Date()
                self.apply(sourceText: source, previews: previews, clipboard: clipboard)
            }
        }
    }

    /// 收起
    public func hide() {
        // 作废在途的唤出（抓选区是异步的），避免它稍后又把面板推出来
        showGeneration += 1
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        toastTask?.cancel()
        toastTask = nil
        revealFallback?.cancel()
        revealFallback = nil
        isRevealed = false
        contentReady = false
        model.toast = nil
        log.notice("超级面板已收起")
    }

    /// 内容量好后一次性显形
    private func reveal() {
        guard !isRevealed, let panel else { return }
        isRevealed = true
        revealFallback?.cancel()
        revealFallback = nil
        panel.alphaValue = 1
        log.debug("超级面板已显形，高度 \(Int(panel.frame.height), privacy: .public)")
    }

    /// 真正推到前台并取焦点
    private func presentPanel(_ panel: SuperPanelPanel) {
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        // 菜单栏/其他窗口刚失活时首次 makeKey 可能不生效，下一轮 runloop 补一次
        Task { @MainActor [weak self, weak panel] in
            guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
            panel.makeKeyAndOrderFront(nil)
            self?.log.debug("超级面板首次未取得 key window，补一次 makeKeyAndOrderFront")
        }
    }

    private func apply(sourceText: String, previews: [SmartPreview], clipboard: String) {
        let actionContext = SuperPanelActionContext(
            copy: { [weak self] text in self?.copy(text) },
            replaceOriginal: { [weak self] text in self?.replaceOriginal(with: text) },
            navigate: { [weak self] pluginID in self?.navigate(to: pluginID) },
            openURL: { [weak self] url in self?.open(url) },
            dismiss: { [weak self] in self?.hide() }
        )
        let actions = SuperPanelContextBuilder.actions(
            previews: previews, sourceText: sourceText, context: actionContext)

        model.apply(
            sourceText: sourceText,
            previews: previews,
            actions: actions,
            recentItems: recentItems?() ?? [],
            latestClipboard: clipboard,
            quickTools: SuperPanelQuickTools.load(),
            showRecents: Self.boolPreference(SuperPanelPreferences.Key.showRecents, default: true),
            showClipboard: Self.boolPreference(SuperPanelPreferences.Key.showClipboard, default: true),
            appearance: SuperPanelPreferences.appearance()
        )

        log.notice(
            "超级面板识别完成：文本长度 \(sourceText.count, privacy: .public)，预览 \(previews.count, privacy: .public) 条")

        // 内容就绪：下一次布局回调（或兜底）就把面板显形
        contentReady = true
        revealFallback?.cancel()
        revealFallback = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            self?.reveal()
        }
    }

    private static func boolPreference(_ key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    // MARK: - 高度自适应

    /// 内容量出自然高度后调整窗口，并以光标为锚点重定位
    private func adjustHeight(to contentHeight: CGFloat) {
        guard let panel, let placement, let visibleFrame = targetVisibleFrame,
            contentHeight > 0
        else { return }

        let height = min(max(contentHeight, SuperPanelMetrics.minHeight), SuperPanelMetrics.maxHeight)
        let size = CGSize(width: SuperPanelMetrics.width, height: height)
        if abs(panel.frame.height - height) > 1 {
            panel.setContentSize(size)
            panel.setFrameOrigin(placement.origin(for: size, visibleFrame: visibleFrame))
        }
        // 内容就绪后第一次量到高度就显形；还没就绪时保持透明（用户看不到撑高的过程）
        if contentReady { reveal() }
    }

    // MARK: - 动作

    private func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        model.toast = "已复制"
        log.debug("超级面板复制文本，长度 \(text.count)")
        // 与 Fasty 一致：给一眼确认，随即收起
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func replaceOriginal(with text: String) {
        let target = previousApp
        hide()
        guard let canPaste, canPaste(), let paste else {
            // 没有辅助功能权限：至少把内容放进剪贴板，别让用户白操作
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(text, forType: .string)
            EventBus.shared.post(ShowHUDEvent(message: "已复制，开启辅助功能权限后可自动替换", tone: .warning))
            return
        }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        target?.activate()
        Task { @MainActor in
            try? await Task.sleep(for: Self.pasteSettleDelay)
            paste()
        }
        log.notice("超级面板替换原文，长度 \(text.count)")
    }

    private func navigate(to pluginID: String) {
        let target = previousApp
        // 把识别到的文本一起带过去：目标插件在 `makeView()` 上挂了
        // `.prefillFromPluginContext(buffer)`，出现时会把 `query` 填进输入框。
        let text = model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        hide()
        target?.activate()
        var context: [String: String] = ["from": "super-panel"]
        if !text.isEmpty { context["query"] = text }
        EventBus.shared.post(NavigateEvent(pluginID: pluginID, context: context))
        log.notice(
            "超级面板跳转插件 \(pluginID, privacy: .public)，携带文本长度 \(text.count, privacy: .public)")
    }

    private func open(_ url: URL) {
        hide()
        NSWorkspace.shared.open(url)
    }

    private func openSettingsWindow() {
        hide()
        openSettings?()
    }

    private func launch(tool: SuperPanelQuickTool) {
        navigate(to: tool.pluginID)
    }

    private func activate(recent item: SuperPanelRecentItem) {
        switch item.kind {
        case .app:
            hide()
            if let path = item.launchPath {
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
            }
        case .plugin:
            if let pluginID = item.pluginID { navigate(to: pluginID) }
        case .command:
            hide()
        }
    }

    // MARK: - 键盘路由

    private func handleEscape() -> Bool {
        hide()
        return true
    }

    private func handleMove(_ delta: Int) -> Bool {
        model.moveSelection(delta)
    }

    private func handleTab() -> Bool {
        guard model.hasContext else { return false }
        model.toggleTab()
        return true
    }

    private func handleSubmit() -> Bool {
        switch model.activeTab {
        case .context:
            guard model.actions.indices.contains(model.selectedIndex) else { return false }
            model.actions[model.selectedIndex].execute()
        case .dock:
            guard model.quickTools.indices.contains(model.selectedIndex) else { return false }
            launch(tool: model.quickTools[model.selectedIndex])
        }
        return true
    }

    private func handleNumber(_ index: Int) -> Bool {
        switch model.activeTab {
        case .context:
            guard model.actions.indices.contains(index) else { return false }
            model.actions[index].execute()
        case .dock:
            guard model.quickTools.indices.contains(index) else { return false }
            launch(tool: model.quickTools[index])
        }
        return true
    }

    private func handleReplace() -> Bool {
        let text = model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        replaceOriginal(with: text)
        return true
    }

    // MARK: - 面板创建与监视

    private func ensurePanel() {
        guard panel == nil else { return }

        let root = SuperPanelRootView(
            model: model,
            onContentHeightChange: { [weak self] height in self?.adjustHeight(to: height) },
            onOpenSettings: { [weak self] in self?.openSettingsWindow() },
            onClose: { [weak self] in self?.hide() },
            onLaunchTool: { [weak self] tool in self?.launch(tool: tool) },
            onRecentItem: { [weak self] item in self?.activate(recent: item) },
            onReplaceWithClipboard: { [weak self] text in self?.replaceOriginal(with: text) },
            onCopyClipboard: { [weak self] text in self?.copy(text) }
        )

        let panel = SuperPanelPanel(rootView: root)
        panel.onEscape = { [weak self] in self?.handleEscape() ?? false }
        panel.onMove = { [weak self] delta in self?.handleMove(delta) ?? false }
        panel.onTab = { [weak self] _ in self?.handleTab() ?? false }
        panel.onSubmit = { [weak self] in self?.handleSubmit() ?? false }
        panel.onNumber = { [weak self] index in self?.handleNumber(index) ?? false }
        panel.onReplace = { [weak self] in self?.handleReplace() ?? false }
        panel.onOpenSettings = { [weak self] in
            self?.openSettingsWindow()
            return true
        }
        panel.onClose = { [weak self] in self?.hide() }

        observeOutsideClicks(on: panel)
        observeResignKey(panel)
        self.panel = panel
        log.debug("超级面板窗口已创建")
    }

    /// 面板外点击收起（与主面板同一套：全局 + 本地两个监视器）
    private func observeOutsideClicks(on panel: SuperPanelPanel) {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hideIfVisible() }
        }

        outsideClickLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self, weak panel] event in
            MainActor.assumeIsolated {
                guard let self, let panel else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.hideIfVisible()
                }
            }
            return event
        }
    }

    /// 失焦收起（带保护期，避开「刚弹出就被底层窗口抢焦」）
    private func observeResignKey(_ panel: SuperPanelPanel) {
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let shownAt = self.shownAt else { return }
                let elapsed = Date().timeIntervalSince(shownAt)
                guard elapsed > Self.focusProtection else {
                    self.log.debug("超级面板处于失焦保护期（\(Int(elapsed * 1000))ms），忽略")
                    return
                }
                self.hideIfVisible()
            }
        }
    }

    private func hideIfVisible() {
        guard isVisible else { return }
        log.notice("超级面板失焦或检测到外部点击，收起")
        hide()
    }
}
