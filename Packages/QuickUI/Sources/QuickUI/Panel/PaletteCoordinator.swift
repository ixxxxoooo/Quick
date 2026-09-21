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

    private let log = QuickLog.palette

    /// 被面板遮挡前的前台应用（用于恢复焦点）
    private var previousApp: NSRunningApplication?

    /// 面板实例（延迟创建）
    private var panel: PalettePanel?

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

    /// 面板即将显示 / 已经隐藏（由 AppCore 注入，用于强制键盘布局这类宿主行为）
    public var onPanelWillShow: (() -> Void)?
    public var onPanelDidHide: (() -> Void)?

    /// 最近使用（由 AppCore 注入；没有存储时为空实现）
    ///
    /// 首屏顺序依赖它，所以它必须是宿主级的：应用、命令、工具条目都在同一张表里。
    public var usageHistory: UsageHistory?

    /// 面板外点击的监视器
    ///
    /// 与协调器同生命周期（进程级），所以不主动摘除 —— 面板一旦创建就一直存在。
    private var outsideClickMonitor: Any?

    /// 分离面板回调（由 AppCore 注入，协调器不直接持有 PluginPanelController）
    public var onDetach: ((String) -> Void)?

    public init() {
        observeClipboardChanges()
    }

    // MARK: - 插件注册

    /// 设置插件列表（AppCore 组装时调用一次）
    /// - Parameter plugins: 所有已注册的 Feature Plugin
    public func setPlugins(_ plugins: [any QuickPlugin]) {
        self.plugins = plugins
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
            syncPaletteMode(pluginID: pluginID)
        }

        let signpost = QuickLog.signposter(QuickLog.Category.palette)
        let interval = signpost.beginInterval("palette.show")
        let started = Date()

        // 面板打开前的自动行为：先按时间窗决定搜索框内容，再显示
        applyAutoBehavior()

        // 宿主行为（例如强制键盘布局）在面板真正出现之前生效
        onPanelWillShow?()

        previousApp = NSWorkspace.shared.frontmostApplication
        ensurePanel()
        positionOnCursorScreen()
        presentPanel()

        signpost.endInterval("palette.show", interval)
        let elapsedMS = Date().timeIntervalSince(started) * 1000
        log.info(
            """
            面板已显示：插件=\(self.activePluginID ?? "主搜索", privacy: .public)，\
            耗时 \(elapsedMS, format: .fixed(precision: 1)) ms
            """)
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
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        // 确保搜索框获得焦点：遍历找到 NSTextField 并使其成为第一响应者
        focusSearchField(in: panel)

        // 菜单栏点击后应用会失活，首次 makeKey 可能不生效；下一轮 runloop 补一次。
        // 这正是 PalettePanel.hidesOnDeactivate = false 要配合的场景。
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
        let wasVisible = isVisible
        panel?.orderOut(nil)

        if restoreFocus, let app = previousApp, !app.isTerminated {
            app.activate()
        }
        previousApp = nil
        onPanelDidHide?()

        if wasVisible {
            log.info("面板已隐藏，恢复焦点=\(restoreFocus, privacy: .public)")
        }
    }

    /// 导航到指定插件
    /// - Parameters:
    ///   - pluginID: 目标插件 ID
    ///   - context: 附加上下文
    public func navigate(to pluginID: String, context: [String: String] = [:]) {
        activePluginID = pluginID
        query = context["query"] ?? ""
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
        paletteMode.navigate(to: pluginID, name: name, icon: icon, context: context)
    }

    // MARK: - 搜索

    /// 单次搜索的结果上限
    ///
    /// 没有上限时，一个失控的插件会把几千条塞进 SwiftUI 列表、还要在主线程排序。
    private static let resultLimit = 60

    /// 单个插件的搜索超时
    ///
    /// 插件的 `searchItems` 跑在主 actor 上（协议本身是 `@MainActor`），
    /// 所以一个慢查询（EventKit、Spotlight、定位）会把**整批**结果卡住 ——
    /// 聚合是等所有插件都返回才结束的。超时之后放弃这个插件，
    /// 而不是让整块面板陪它等。
    private static let pluginTimeout = Duration.seconds(2)

    /// 聚合搜索：查询所有已启用插件
    ///
    /// - Parameter query: 搜索关键词
    /// - Returns: 去重、排序、限流之后的结果
    public func search(query: String) async -> [SearchableItem] {
        let enabledPlugins = plugins.filter(\.isEnabled)

        let signpost = QuickLog.signposter(QuickLog.Category.palette)
        let interval = signpost.beginInterval("palette.search")
        let started = Date()

        let collected = await withTaskGroup(of: [SearchableItem].self) { group in
            for plugin in enabledPlugins {
                let pluginName = type(of: plugin).name
                group.addTask {
                    let items = await Self.search(plugin: plugin, query: query)
                    // 给每条搜索结果标注来源插件名
                    return items.map { $0.pluginName == nil ? $0.withPluginName(pluginName) : $0 }
                }
            }
            var results: [SearchableItem] = []
            for await items in group {
                results.append(contentsOf: items)
            }
            return results
        }

        // 去重：`SearchableItem` 的 `Hashable` 只看 id，而「id 以插件 id 开头」
        // 只是一条约定，没有任何东西在强制它。重复 id 会让 `ForEach` 进入未定义行为
        // （丢行、选中高亮错位），所以在这里挡一道。
        var seen = Set<String>()
        let deduped = collected.filter { seen.insert($0.id).inserted }

        // 排序：相关度降序，**同分时按 id 升序**。
        // 只按相关度排的话同分项的顺序由任务完成顺序决定，而常量相关度
        // （0.5 / 0.6 是常态）意味着同分是多数情况 —— 那等于没有顺序保证，
        // 列表每次刷新都可能换一个样子。
        var sorted = deduped.sorted {
            $0.relevance == $1.relevance ? $0.id < $1.id : $0.relevance > $1.relevance
        }

        // 首屏（空查询）把「最近用过的」提到最前。
        //
        // 首屏是「我刚用过什么」的入口，不是「谁的分数高」的排行榜 —— 昨天启动过 20 次的
        // 应用，不该排在刚刚用过的翻译前面。非空查询不动顺序：那时相关度才是用户要的。
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sorted = Self.promotingRecents(sorted, recents: usageHistory?.recentItemIDs(limit: 12) ?? [])
        }

        let limited = Array(sorted.prefix(Self.resultLimit))

        signpost.endInterval("palette.search", interval)
        let elapsedMS = Date().timeIntervalSince(started) * 1000
        log.debug(
            """
            聚合搜索完成：\(enabledPlugins.count, privacy: .public) 个插件，\
            命中 \(collected.count, privacy: .public) 条 → \
            去重后 \(deduped.count, privacy: .public) 条 → \
            返回 \(limited.count, privacy: .public) 条，\
            耗时 \(elapsedMS, format: .fixed(precision: 1)) ms
            """)

        return limited
    }

    /// 把最近使用过的条目提到前面，其余保持原顺序
    ///
    /// 抽成静态函数是为了能单独测：这里只做重排，不碰数据库、不碰插件。
    static func promotingRecents(
        _ items: [SearchableItem],
        recents: [String]
    ) -> [SearchableItem] {
        guard !recents.isEmpty else { return items }

        let rank = Dictionary(uniqueKeysWithValues: recents.enumerated().map { ($1, $0) })
        let (recent, rest) = items.reduce(into: ([SearchableItem](), [SearchableItem]())) {
            if rank[$1.id] != nil { $0.0.append($1) } else { $0.1.append($1) }
        }
        // 按「最近」的顺序排，而不是按它们原来的相关度 —— 这里要的就是时间顺序
        return recent.sorted { (rank[$0.id] ?? 0) < (rank[$1.id] ?? 0) } + rest
    }

    /// 查询单个插件，超时即放弃
    ///
    /// 竞速两个子任务：插件自己，和一个超时计时器。先完成的那个决定结果。
    /// 注意超时**不会**中断插件内部的同步工作（它在主 actor 上），
    /// 只是让我们不再等它 —— 这正是需要的：面板不能陪一个慢插件等下去。
    ///
    /// **空查询走 `defaultItems()` 而不是 `searchItems(query: "")`**：插件在空查询上被
    /// 触发词闸门挡住，返回的都是空数组 —— 那样首屏就只剩应用，一条命令都没有。
    /// 首屏该展示什么由插件自己说（见 `QuickPlugin.defaultItems`）。
    private static func search(plugin: any QuickPlugin, query: String) async -> [SearchableItem] {
        let wantsDefaults = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return await withTaskGroup(of: [SearchableItem].self) { group in
            group.addTask {
                if wantsDefaults {
                    return await plugin.defaultItems()
                }
                return await plugin.searchItems(query: query)
            }
            group.addTask {
                try? await Task.sleep(for: Self.pluginTimeout)
                return []
            }
            let first = await group.next() ?? []
            group.cancelAll()
            return first
        }
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
            searchHandler: { [weak self] query in
                guard let self else { return [] }
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

        // 上下键与回车在 AppKit 层转给选中状态，见 PalettePanel.sendEvent 的说明。
        //
        // **插件模式下不接。** 那时屏幕上是插件的视图，方向键与回车属于它 —— 它有焦点、
        // 有自己的标签栏和列表；而搜索列表的选中项还停在最后一次搜索上，让它接管既吃掉了
        // 插件该收的键，又可能把回车打到一条用户早已看不见的结果上。返回 false 就是让事件
        // 继续往响应链上走，由插件的视图处理。
        newPanel.onMove = { [weak self] delta in
            guard let self, self.activePluginID == nil else { return false }
            return self.selection.move(delta)
        }
        newPanel.onSubmit = { [weak self] in
            guard let self, self.activePluginID == nil else { return false }
            return self.selection.activateSelection()
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

    /// 点击面板以外的位置时收起
    ///
    /// **用事件监视器，不用 `didResignKey`。** 后者把「任何原因导致的失焦」都当成
    /// 用户在点别处 —— 例如某个插件在启动时弹出的系统权限对话框也会抢走键盘焦点，
    /// 于是面板会在启动几秒后自己消失。用户要的只是「点空白处关掉」，
    /// 那就精确地只对「点击」作出反应。
    ///
    /// **只装全局监视器。** 它收到的是发往其他应用的事件，也就是「点到别的应用去了」，
    /// 这正好是用户说的「空白处」。曾经还装过一个本地监视器来处理「点了本应用的其他
    /// 窗口」，但它会收到启动阶段某些非用户发起的事件，导致面板刚显示就被收起 ——
    /// 与其猜哪些本地事件算数，不如不做：点设置窗口时面板不收，代价小得多。
    ///
    /// 鼠标事件不需要辅助功能权限（键盘事件才需要）。
    private func observeOutsideClicks(on panel: PalettePanel) {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hideIfVisible() }
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
    private func makePluginView(pluginID: String, context: [String: String]) -> AnyView? {
        guard let plugin = plugins.first(where: { type(of: $0).id == pluginID }),
            plugin.isEnabled
        else {
            log.warning("找不到插件 \(pluginID, privacy: .public) 或插件已禁用")
            return nil
        }
        return plugin.makeView()
    }

    /// 将面板定位到光标所在屏幕的中上方
    private func positionOnCursorScreen() {
        guard let panel else { return }
        // 屏幕按鼠标位置选：多显示器下这是唯一能反映「用户此刻在看哪块屏」的信号，
        // 见 `ScreenPlacement`。
        let screen = ScreenPlacement.screen() ?? NSScreen.main ?? NSScreen.screens.first

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
}
