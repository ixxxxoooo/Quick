// PaletteCoordinator.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 面板协调器
///
/// 管理面板的显隐、定位、模式切换。
/// 不持有任何业务逻辑，只负责面板的生命周期和路由。
/// 注意：不要标记为 @Observable——宿主 NSPanel 持有的 SwiftUI 视图若观察本对象，
/// 会与 AttributeGraph 形成死循环（CPU 100%）。
@MainActor
public final class PaletteCoordinator {

    /// 当前活跃的插件 ID（nil 表示主搜索模式）
    public private(set) var activePluginID: String?

    /// 面板是否可见
    public var isVisible: Bool { panel?.isVisible ?? false }

    /// 搜索框文本
    ///
    /// 转发到 `paletteQuery`：面板内外只有这一份查询状态，避免「协调器以为输入框里是 A、
    /// 输入框里其实是 B」。
    public var query: String {
        get { paletteQuery.text }
        set { paletteQuery.text = newValue }
    }

    /// 搜索框文本的持有者（视图与协调器共用）
    public let paletteQuery = PaletteQuery()

    /// 面板模式状态（供 SwiftUI 观察的桥接对象）
    ///
    /// 协调器本身不能被 SwiftUI 观察（会死循环），但视图需要知道
    /// 当前是搜索模式还是插件模式。这个对象只持有纯状态，安全观察。
    public let paletteMode = PaletteMode()

    /// 当前插件的「插件内搜索」状态（供支持搜索的插件视图观察）
    ///
    /// 与 `paletteQuery` 分开：主搜索的查询与插件内搜索是两回事，进入/离开插件时
    /// 都要清掉，否则一个插件过滤过的词会漏进下一个插件。
    public let pluginSearch = PluginSearchQuery()

    private let log = QuickLog.palette

    /// 被面板遮挡前的前台应用（用于恢复焦点）
    private var previousApp: NSRunningApplication?

    /// 面板实例（延迟创建）
    private var panel: PalettePanel?

    /// 上次套用的缩放档，用来识别「换档」并据此丢掉手动拖出来的尺寸
    private var lastScale: CGFloat?

    /// 所有已注册插件（由 AppCore 注入）
    private var plugins: [any QuickPlugin] = []

    /// 面板里的选中状态
    ///
    /// 放在这里而不是视图里，是因为上下键必须在 AppKit 层（`PalettePanel.sendEvent`）
    /// 拦截，而拦截方需要一个能读写「选中第几项」的地方。它**不持有窗口**，
    /// 所以被 SwiftUI 观察是安全的 —— 会死循环的是协调器本身。
    public let selection = PaletteSelection()

    /// 剪贴板最后一次变化的时刻（由剪贴板事件更新）
    ///
    /// 自动粘贴只关心「刚刚复制过」，而这个时间点只有剪贴板插件知道（它在轮询变化），
    /// 所以它发事件、这里记时间。
    private var lastClipboardChange: Date?

    /// 剪贴板事件的订阅凭证
    private var clipboardSubscription: EventSubscription?

    /// 面板即将显示 / 已经隐藏（由宿主注入，用于强制键盘布局这类宿主行为）
    ///
    /// 只读：接线在 `AppCore.start()` 一次性完成，之后不再变更。见 `PaletteDependencies` 的说明。
    public var onPanelWillShow: (() -> Void)? { dependencies?.onPanelWillShow }
    public var onPanelDidHide: (() -> Void)? { dependencies?.onPanelDidHide }

    /// 最近使用（由宿主注入；没有存储时为空实现）
    ///
    /// 首屏顺序依赖它，所以它必须是宿主级的：应用、命令、工具条目都在同一张表里。
    public var usageHistory: UsageHistory? { dependencies?.usageHistory }

    /// 分离面板回调（协调器不直接持有 PluginPanelController）
    public var onDetach: ((String) -> Void)? { dependencies?.onDetach }

    /// 静态命令快照。搜索热路径只读它，不遍历插件对象
    public var staticCommands: [IndexedCommand] = []

    /// 某个插件是否参与主搜索
    public var isSearchSourceEnabled: (String) -> Bool { dependencies?.isSearchSourceEnabled ?? { _ in true } }

    /// 宿主自己的搜索来源（文件搜索）
    ///
    /// 它不是插件，所以不走 `plugins` 那一条；但结果与插件结果在同一个任务组里汇总，
    /// 排序、去重、限流、超时规则完全一致。
    public var hostSearchSource: (any PaletteHostSearchSource)? { dependencies?.hostSearchSource }

    /// 命中静态命令时的执行入口
    ///
    /// `@Sendable` 是必需的：它会被存进 `SearchableItem.action`，而那个结构是 `Sendable`。
    public var invokeCommand: @MainActor @Sendable (String) -> Void {
        dependencies?.invokeCommand ?? PaletteCoordinator.noOpInvoke
    }

    /// 未接线时的兜底：什么都不做
    ///
    /// 写成具名函数而不是 `{ _ in }`：闭包字面量在这里推不出 `Sendable`，
    /// 而全局 actor 隔离的函数本身就是 `Sendable` 的，函数引用能直接转换。
    @MainActor
    private static func noOpInvoke(_ commandID: String) {}

    /// 宿主注入的依赖
    ///
    /// `nil` 表示还没接线 —— 这在启动过程中是正常状态，但任何**查询**发生前必须已设好。
    private var dependencies: PaletteDependencies?

    /// 面板外点击的监视器（发往其他应用的点击）
    ///
    /// 与协调器同生命周期（进程级），所以不主动摘除 —— 面板一旦创建就一直存在。
    private var outsideClickMonitor: Any?

    /// 面板外点击的本地监视器（发往本应用其他窗口的点击）
    private var outsideClickLocalMonitor: Any?

    public init() {
        observeClipboardChanges()
    }

    /// 注入宿主依赖
    ///
    /// **只调用一次**，由 `AppCore.start()` 在插件注册之后接线。重复调用会打
    /// `.fault` —— 那意味着有人试图在运行期改依赖，而这正是本类型要消灭的模式。
    /// - Parameter dependencies: 宿主的全部外部依赖
    public func attach(_ dependencies: PaletteDependencies) {
        guard self.dependencies == nil else {
            log.fault("PaletteDependencies 被重复注入，后一次已忽略")
            return
        }
        self.dependencies = dependencies
    }

    // MARK: - 插件注册

    /// 设置插件列表（AppCore 组装时调用一次）
    /// - Parameter plugins: 所有已注册的 Feature Plugin
    public func setPlugins(_ plugins: [any QuickPlugin]) {
        self.plugins = plugins
    }

    /// 启动时预热面板
    ///
    /// 首次 `ensurePanel` 需要创建 NSPanel + NSHostingView + SwiftUI 视图树，
    /// 实测 13 ms。推到首次 show 会被用户感知为延迟，挪到启动阶段吸收掉。
    public func prewarm() {
        ensurePanel()
        log.debug("面板预热完成")
    }

    // MARK: - 面板控制

    /// 切换面板显隐
    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// 显示面板（带插件切换）
    /// - Parameters:
    ///   - pluginID: 目标插件 ID（nil 表示主搜索）
    ///   - query: 预填搜索文本
    public func show(pluginID: String? = nil, query: String? = nil) {
        if let query { self.query = query }

        if let pluginID {
            activePluginID = pluginID
            pluginSearch.reset()
            syncPaletteMode(pluginID: pluginID)
        }

        let signpost = QuickLog.signposter(QuickLog.Category.palette)
        let interval = signpost.beginInterval("palette.show")
        let started = ContinuousClock.now

        // 自动粘贴 / 自动清空只在主搜索模式下有意义；打开特定插件时跳过，
        // 避免剪贴板内容被填进搜索框后触发粘贴检测（JSON/SQL 跳转），
        // 把 activePluginID 篡改成 json-formatter/sql-formatter，导致
        // 再次按快捷键时切换（关闭）逻辑匹配不上。
        if pluginID == nil {
            let t0 = ContinuousClock.now
            applyAutoBehavior()
            let autoBehaviorMS = t0.duration(to: .now).ms
            if autoBehaviorMS > 5 {
                log.warning("show 子步骤慢：applyAutoBehavior \(autoBehaviorMS, format: .fixed(precision: 1)) ms")
            }
        }

        previousApp = NSWorkspace.shared.frontmostApplication

        let t2 = ContinuousClock.now
        ensurePanel()
        let ensurePanelMS = t2.duration(to: .now).ms
        if ensurePanelMS > 5 {
            log.warning("show 子步骤慢：ensurePanel \(ensurePanelMS, format: .fixed(precision: 1)) ms")
        }

        applyPaletteMetrics()
        positionOnCursorScreen()

        let t3 = ContinuousClock.now
        presentPanel()
        let presentMS = t3.duration(to: .now).ms
        if presentMS > 5 {
            log.warning("show 子步骤慢：presentPanel \(presentMS, format: .fixed(precision: 1)) ms")
        }

        // 键盘布局切换（~10 ms）放在 presentPanel 之后：面板先出现，布局再切。
        // 人类反应时间 > 200 ms，不可能在 10 ms 内开始打字，所以不影响体验。
        // 放在 presentPanel 之前时，10 ms 的系统调用全部变成了面板出现的感知延迟。
        onPanelWillShow?()

        signpost.endInterval("palette.show", interval)
        let totalMS = started.duration(to: .now).ms
        log.notice(
            """
            面板已显示：插件=\(self.activePluginID ?? "主搜索", privacy: .public)，\
            总耗时 \(totalMS, format: .fixed(precision: 1)) ms
            """)

        EventBus.shared.post(PaletteVisibilityChangedEvent(isVisible: true))
    }

    /// 打开面板时的自动行为
    ///
    /// 两件事都靠 `PaletteAutoBehavior` 里的纯函数判定，这里只负责取数据与落结果：
    /// - 刚复制过东西 → 填进搜索框（用户唤出面板多半就是要用它）
    /// - 上次的查询放太久了 → 清掉（否则每次打开都看到上次残留的关键词）
    ///
    /// 两个设置都经 `PaletteAutoBehavior` 读，不直接 `integer(forKey:)` —— 那样会把
    /// 「没设置过」读成 0（关闭），和设置页显示的默认值对不上。
    private func applyAutoBehavior() {
        let defaults = UserDefaults.standard
        let now = Date()

        // 自动清空先做：清掉之后搜索框是空的，自动粘贴才有机会填进去
        let clearIdle = PaletteAutoBehavior.clearIdle(from: defaults)
        if PaletteAutoBehavior.shouldClearStaleQuery(
            lastEditedAt: paletteQuery.lastEditedAt,
            now: now,
            idleMinutes: clearIdle.rawValue,
            currentQuery: query)
        {
            log.debug("搜索框内容已超过 \(clearIdle.rawValue, privacy: .public) 分钟未改动，自动清空")
            query = ""
        }

        let pasteWindow = PaletteAutoBehavior.pasteWindow(from: defaults)
        let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
        if PaletteAutoBehavior.shouldPrefillFromClipboard(
            lastClipboardChange: lastClipboardChange,
            now: now,
            window: TimeInterval(pasteWindow.rawValue),
            clipboardText: clipboardText,
            currentQuery: query)
        {
            log.debug("剪贴板内容在 \(pasteWindow.rawValue, privacy: .public) 秒内变化过，已填入搜索框")
            query = clipboardText
        }
    }

    /// 订阅剪贴板变化事件（只在有需要时记一个时间点）
    private func observeClipboardChanges() {
        guard clipboardSubscription == nil else { return }
        clipboardSubscription = EventBus.shared.on(ClipboardChangedEvent.self) { [weak self] event in
            self?.lastClipboardChange = event.at
        }
    }

    /// 将面板真正推到前台
    private func presentPanel() {
        guard let panel else { return }

        let t0 = ContinuousClock.now
        panel.makeKeyAndOrderFront(nil)
        let makeKeyMS = t0.duration(to: .now).ms

        let t1 = ContinuousClock.now
        panel.orderFrontRegardless()
        let orderFrontMS = t1.duration(to: .now).ms

        let t2 = ContinuousClock.now
        NSApp.activate(ignoringOtherApps: true)
        let activateMS = t2.duration(to: .now).ms

        focusSearchField(in: panel)

        if makeKeyMS > 3 || orderFrontMS > 3 || activateMS > 3 {
            log.warning(
                """
                presentPanel 子步骤：makeKey \(makeKeyMS, format: .fixed(precision: 1)), \
                orderFront \(orderFrontMS, format: .fixed(precision: 1)), \
                activate \(activateMS, format: .fixed(precision: 1)) ms
                """)
        }

        Task { @MainActor [weak self, weak panel] in
            guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
            self?.log.debug("面板首次未取得 key window，补一次 makeKeyAndOrderFront")
            panel.makeKeyAndOrderFront(nil)
            self?.focusSearchField(in: panel)
        }
    }

    /// 将焦点强制设给面板中的搜索框
    private func focusSearchField(in panel: NSPanel) {
        guard let contentView = panel.contentView else { return }
        if let textField = findTextField(in: contentView) {
            panel.makeFirstResponder(textField)
        }
    }

    /// 递归查找第一个 NSTextField
    private func findTextField(in view: NSView) -> NSTextField? {
        if let textField = view as? NSTextField, textField.isEditable {
            return textField
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview) {
                return found
            }
        }
        return nil
    }

    /// 隐藏面板
    /// - Parameter restoreFocus: 是否恢复之前应用的焦点
    public func hide(restoreFocus: Bool = true) {
        let started = ContinuousClock.now
        let wasVisible = isVisible

        // 视觉消失必须同步：用户按键后面板要立刻从屏幕上移走
        panel?.orderOut(nil)
        let orderOutMS = started.duration(to: .now).ms

        if wasVisible {
            // 焦点恢复和键盘布局还原不影响「面板消失」的视觉反馈，
            // 推迟到下一轮 runloop 避免阻塞主线程（键盘布局切换实测 12~15 ms）
            let app = restoreFocus ? previousApp : nil
            let didHideCallback = onPanelDidHide
            previousApp = nil

            Task { @MainActor [weak self] in
                let postStart = ContinuousClock.now
                if let app, !app.isTerminated {
                    app.activate()
                }
                didHideCallback?()
                let postMS = postStart.duration(to: .now).ms
                if postMS > 5 {
                    self?.log.debug("hide 异步后处理：\(postMS, format: .fixed(precision: 1)) ms")
                }
            }

            log.notice(
                """
                面板已隐藏（同步阶段）：orderOut \(orderOutMS, format: .fixed(precision: 1)) ms，\
                恢复焦点=\(restoreFocus, privacy: .public)
                """)
            EventBus.shared.post(PaletteVisibilityChangedEvent(isVisible: false))
        } else {
            previousApp = nil
        }
    }

    /// 导航到指定插件
    /// - Parameters:
    ///   - pluginID: 目标插件 ID
    ///   - context: 附加上下文
    public func navigate(to pluginID: String, context: [String: String] = [:]) {
        activePluginID = pluginID
        query = context["query"] ?? ""
        pluginSearch.reset()
        syncPaletteMode(pluginID: pluginID, context: context)

        if !isVisible {
            show()
        }
    }

    /// 返回主搜索模式
    ///
    /// 从插件退回主搜索时**必须把焦点交还搜索框**：插件视图被销毁后第一响应者也随之消失，
    /// 不重新指定的话用户接下来打的字没有任何地方接收 —— 看起来像输入框坏了。
    /// 焦点要等 SwiftUI 把搜索模式的视图重建出来之后再设，所以延到下一轮 runloop。
    public func popToRoot() {
        activePluginID = nil
        query = ""
        pluginSearch.reset()
        paletteMode.popToRoot()

        guard let panel else { return }
        Task { @MainActor [weak self, weak panel] in
            guard let panel else { return }
            self?.focusSearchField(in: panel)
        }
    }

    // MARK: - Esc

    /// 按下 Esc 时该做的事
    public enum EscapeAction: Equatable, Sendable {
        /// 插件模式：退回主搜索
        case popToRoot
        /// 搜索模式且搜索框有内容：清空输入
        case clearQuery
        /// 搜索模式且搜索框为空：收起面板
        case dismiss
    }

    /// Esc 的动作决策
    ///
    /// 抽成纯函数是为了能单独测：三层优先级（插件 → 有输入 → 关闭）里，
    /// 任何一层写错都会表现成「Esc 莫名其妙把面板关了」，而那是最难当场复现的一类问题。
    ///
    /// 「有内容」按原样判空，不 trim —— 与搜索框右侧那个 ✕ 清空按钮的显示条件
    /// （`!query.isEmpty`）保持一致，用户看到的清空按钮在什么时候出现，
    /// Esc 就在什么时候清空。
    public static func escapeAction(isPluginMode: Bool, query: String) -> EscapeAction {
        if isPluginMode { return .popToRoot }
        return query.isEmpty ? .dismiss : .clearQuery
    }

    /// 执行 Esc：有输入先清空，没输入才关面板
    ///
    /// 搜索框里有内容时 Esc 只清空，不关面板 —— 关掉整个面板的代价太大，
    /// 而用户按下 Esc 时多半只是想重打一个关键词。
    func handleEscape() {
        switch Self.escapeAction(isPluginMode: activePluginID != nil, query: query) {
        case .popToRoot:
            popToRoot()
        case .clearQuery:
            log.debug("Esc 清空搜索框")
            query = ""
        case .dismiss:
            hide()
        }
    }

    /// 将协调器的插件状态同步到 PaletteMode
    ///
    /// 从 plugins 中查找对应插件的元信息（名称、图标），一并写入 PaletteMode。
    private func syncPaletteMode(pluginID: String, context: [String: String] = [:]) {
        let plugin = plugins.first { type(of: $0).id == pluginID }
        let name = plugin.map { type(of: $0).name } ?? pluginID
        let icon = plugin.map { type(of: $0).icon } ?? "questionmark"
        let supportsSearch = plugin.map { type(of: $0).supportsPanelSearch } ?? false
        paletteMode.navigate(
            to: pluginID,
            name: name,
            icon: icon,
            context: context,
            supportsSearch: supportsSearch
        )
    }

    // MARK: - 搜索

    /// 聚合搜索入口：依赖注入后委托给 `PaletteSearchEngine`
    public func search(query: String) async -> PaletteSearchOutcome {
        await PaletteSearchEngine.search(
            query: query,
            staticCommands: staticCommands,
            plugins: plugins,
            isSearchSourceEnabled: isSearchSourceEnabled,
            recentItemIDs: usageHistory?.recentItemIDs(limit: 12) ?? [],
            invokeCommand: invokeCommand,
            log: log,
            hostSource: hostSearchSource
        )
    }

    // MARK: - 内部方法

    /// 确保面板已创建
    private func ensurePanel() {
        guard panel == nil else { return }
        log.debug("首次创建面板实例")
        let rootView = PaletteRootView(
            selection: selection,
            paletteQuery: paletteQuery,
            paletteMode: paletteMode,
            pluginSearch: pluginSearch,
            searchHandler: { [weak self] query in
                guard let self else { return .empty }
                return await self.search(query: query)
            },
            pluginViewProvider: { [weak self] pluginID, context in
                guard let self else { return nil }
                return self.makePluginView(pluginID: pluginID, context: context)
            },
            onItemActivated: { [weak self] itemID in
                self?.usageHistory?.record(itemID: itemID)
            },
            onReturnToSearch: { [weak self] in
                self?.popToRoot()
            }
        )
        let newPanel = PalettePanel(rootView: rootView)

        newPanel.onEscape = { [weak self] in
            guard let self else { return false }
            self.handleEscape()
            return true
        }

        newPanel.onClose = { [weak self] in
            self?.hide()
        }

        newPanel.onDetach = { [weak self] in
            guard let self, let pluginID = self.activePluginID else { return false }
            self.onDetach?(pluginID)
            return true
        }

        // ⌘F：把焦点交给插件头部的搜索框
        //
        // 头部搜索框默认不聚焦（焦点留在插件视图上，方向键才好用），主动要搜索时才按 ⌘F。
        // 只对声明了插件内搜索的插件生效，其余插件把 ⌘F 放行给它们自己。
        newPanel.onCommandShortcut = { [weak self] event in
            guard let self, event.charactersIgnoringModifiers?.lowercased() == "f" else {
                return false
            }
            return self.requestPluginSearchFocus()
        }

        // 上下键与回车在 AppKit 层转给选中状态，见 PalettePanel.sendEvent 的说明。
        //
        // **插件模式下走另一条路。** 插件声明要吃导航时，把上下 / 左右 / 回车记成
        // `PluginSearchQuery` 的请求，插件视图用 `commandToken` 取走执行；不声明（或自己
        // 把 `wantsNavigation` 置假）就返回 false，事件沿响应链继续走，由插件视图处理。
        newPanel.onMove = { [weak self] delta in
            self?.routeMove(delta) ?? false
        }
        newPanel.onSubmit = { [weak self] in
            self?.routeSubmit() ?? false
        }
        newPanel.onTab = { [weak self] delta in
            self?.routeTab(delta) ?? false
        }
        newPanel.onPointerMoved = { [weak self] location in
            self?.selection.notePointerMoved(to: location)
        }
        newPanel.onDisarmHover = { [weak self] location in
            self?.selection.disarmHover(at: location)
        }

        observeOutsideClicks(on: newPanel)
        panel = newPanel
    }

    // MARK: - 面板按键路由

    /// 上下键：插件模式转给插件内搜索（仅当插件声明要吃），否则给主搜索列表
    func routeMove(_ delta: Int) -> Bool {
        if activePluginID != nil {
            guard pluginSearch.wantsNavigation else { return false }
            pluginSearch.request(.move(delta))
            return true
        }
        return selection.move(delta)
    }

    /// 回车：插件模式下转给插件内搜索，否则激活主搜索选中项
    func routeSubmit() -> Bool {
        if activePluginID != nil {
            guard pluginSearch.wantsNavigation else { return false }
            pluginSearch.request(.submit)
            return true
        }
        return selection.activateSelection()
    }

    /// 左右键：只有插件内搜索需要（主搜索的左右键属于搜索框光标）
    func routeTab(_ delta: Int) -> Bool {
        guard activePluginID != nil, pluginSearch.wantsNavigation else { return false }
        pluginSearch.request(.tab(delta))
        return true
    }

    /// ⌘F：把焦点交给插件头部的搜索框
    ///
    /// 只在插件模式且该插件提供头部搜索框时消费；主搜索里焦点本来就在搜索框，
    /// 其他插件把 ⌘F 留给它们自己。
    func requestPluginSearchFocus() -> Bool {
        guard activePluginID != nil, pluginSearch.hasHeaderField else { return false }
        pluginSearch.requestFocus()
        return true
    }

    /// 点击面板以外的位置时收起
    ///
    /// **用事件监视器，不用 `didResignKey`。** 后者把「任何原因导致的失焦」都当成
    /// 用户在点别处 —— 例如某个插件在启动时弹出的系统权限对话框也会抢走键盘焦点，
    /// 于是面板会在启动几秒后自己消失。用户要的只是「点空白处关掉」，
    /// 那就精确地只对「点击」作出反应。
    ///
    /// 两个监视器都要：**全局**收「点到别的应用」，**本地**收「点到本应用的其他窗口」
    /// （设置窗口、分离窗口）。只装全局时，点设置窗口面板会赖在它上面不收。
    ///
    /// 本地监视器按「点击点是否落在面板框内」判断，而不是见到本地点击就收 ——
    /// 启动阶段有些非用户发起的本地事件，按位置过滤后它们都落在面板内，不会误伤。
    ///
    /// 鼠标事件不需要辅助功能权限（键盘事件才需要）。
    private func observeOutsideClicks(on panel: PalettePanel) {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hideIfVisible() }
        }

        outsideClickLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self, weak panel] event in
            // 本地监视器回调在主线程上，面板与其状态都是主线程隔离的
            MainActor.assumeIsolated {
                guard let self, let panel else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.hideIfVisible()
                }
            }
            // 必须放行：本地监视器会把事件拦下来，返回 nil 的话设置窗口自己也点不动了
            return event
        }
    }

    /// 面板可见时收起（监视器可能在没有面板时被触发）
    private func hideIfVisible() {
        guard isVisible else { return }
        // notice 而不是 debug：用户报「面板自己消失了」时，这一条就是答案，
        // 而 debug 不落盘、事后查不到。
        log.notice("检测到面板外的点击，收起面板")
        hide()
    }

    /// 根据插件 ID 构建插件视图
    ///
    /// 通过闭包注入给 PaletteRootView，避免视图层直接依赖插件。
    ///
    /// 视图能力是运行时查询：插件没实现 `PluginViewProviding` 时面板会是空白，
    /// 所以这条路径必须留一条能看出根因的日志。
    private func makePluginView(pluginID: String, context: [String: String]) -> AnyView? {
        guard let plugin = plugins.first(where: { type(of: $0).id == pluginID }),
            plugin.isEnabled
        else {
            log.warning("找不到插件 \(pluginID, privacy: .public) 或插件已禁用")
            return nil
        }
        guard let provider = plugin as? PluginViewProviding else {
            log.error("插件 \(pluginID, privacy: .public) 未实现 PluginViewProviding，面板无法显示")
            return nil
        }
        return provider.makeView()
    }

    /// 将面板定位到光标所在屏幕的中上方
    private func positionOnCursorScreen() {
        guard let panel else { return }
        // 屏幕按鼠标位置选：多显示器下这是唯一能反映「用户此刻在看哪块屏」的信号，
        // 见 `ScreenPlacement`。
        let screen =
            if PalettePreferences.usesMainScreen {
                NSScreen.main ?? NSScreen.screens.first
            } else {
                ScreenPlacement.screen() ?? NSScreen.main ?? NSScreen.screens.first
            }

        guard let screen else {
            log.warning("找不到可用屏幕，面板位置未调整")
            return
        }

        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y =
            screenFrame.maxY - panelSize.height - screenFrame.height
            * DesignTokens.Size.paletteTopMarginFraction

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        log.debug("面板定位完成，屏幕=\(screen.localizedName, privacy: .public)")
    }

    /// 按外观设置改面板尺寸。内部排版仍按设计令牌，外层再缩放到用户选的档
    public func applyPaletteMetrics() {
        guard let panel else { return }
        let scale = PalettePreferences.scaleFactor
        if let lastScale, lastScale != scale {
            // 换档是显式选择：丢掉手动拖出来的尺寸，回到该档的设计尺寸
            PalettePreferences.clearPanelSize()
        }
        lastScale = scale

        let target = NSSize(width: PalettePreferences.panelWidth, height: PalettePreferences.panelHeight)
        // 尺寸没变就什么都不做。拖拽结束时刚写回的记忆值会触发一次这里，
        // 若照常重排会把用户刚拖好的位置重新居中。
        guard !panel.frame.size.isApproximately(target) else { return }

        panel.setContentSize(target)
        if isVisible {
            positionOnCursorScreen()
        }
    }
}

extension NSSize {
    /// 两个尺寸是否近似相等（写进偏好再读回来会过一遍 Double，不敢用精确比较）
    fileprivate func isApproximately(_ other: NSSize) -> Bool {
        abs(width - other.width) < 0.5 && abs(height - other.height) < 0.5
    }
}

extension Duration {
    /// 转换为毫秒数（双精度），给计时日志用
    fileprivate var ms: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
    }
}
