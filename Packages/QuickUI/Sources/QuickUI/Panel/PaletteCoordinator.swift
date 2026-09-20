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

    /// 当前活跃的模块 ID（nil 表示主搜索模式）
    public private(set) var activeModuleID: String?

    /// 面板是否可见
    public var isVisible: Bool { panel?.isVisible ?? false }

    /// 搜索文本（双向绑定到搜索框）
    public var query: String = ""

    /// 面板模式状态（供 SwiftUI 观察的桥接对象）
    ///
    /// 协调器本身不能被 SwiftUI 观察（会死循环），但视图需要知道
    /// 当前是搜索模式还是模块模式。这个对象只持有纯状态，安全观察。
    public let paletteMode = PaletteMode()

    private let log = QuickLog.palette

    /// 被面板遮挡前的前台应用（用于恢复焦点）
    private var previousApp: NSRunningApplication?

    /// 面板实例（延迟创建）
    private var panel: PalettePanel?

    /// 所有已注册模块（由 AppCore 注入）
    private var modules: [any QuickModule] = []

    /// 面板里的选中状态
    ///
    /// 放在这里而不是视图里，是因为上下键必须在 AppKit 层（`PalettePanel.sendEvent`）
    /// 拦截，而拦截方需要一个能读写「选中第几项」的地方。它**不持有窗口**，
    /// 所以被 SwiftUI 观察是安全的 —— 会死循环的是协调器本身。
    public let selection = PaletteSelection()

    /// 面板外点击的监视器
    ///
    /// 与协调器同生命周期（进程级），所以不主动摘除 —— 面板一旦创建就一直存在。
    private var outsideClickMonitor: Any?

    /// 分离面板回调（由 AppCore 注入，协调器不直接持有 ModulePanelController）
    public var onDetach: ((String) -> Void)?

    public init() {}

    // MARK: - 模块注册

    /// 设置模块列表（AppCore 组装时调用一次）
    /// - Parameter modules: 所有已注册的 Feature Module
    public func setModules(_ modules: [any QuickModule]) {
        self.modules = modules
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

    /// 显示面板（带模块切换）
    /// - Parameters:
    ///   - moduleID: 目标模块 ID（nil 表示主搜索）
    ///   - query: 预填搜索文本
    public func show(moduleID: String? = nil, query: String? = nil) {
        if let query { self.query = query }

        if let moduleID {
            activeModuleID = moduleID
            syncPaletteMode(moduleID: moduleID)
        }

        let signpost = QuickLog.signposter(QuickLog.Category.palette)
        let interval = signpost.beginInterval("palette.show")
        let started = Date()

        previousApp = NSWorkspace.shared.frontmostApplication
        ensurePanel()
        positionOnCursorScreen()
        presentPanel()

        signpost.endInterval("palette.show", interval)
        let elapsedMS = Date().timeIntervalSince(started) * 1000
        log.info(
            """
            面板已显示：模块=\(self.activeModuleID ?? "主搜索", privacy: .public)，\
            耗时 \(elapsedMS, format: .fixed(precision: 1)) ms
            """)
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

        if wasVisible {
            log.info("面板已隐藏，恢复焦点=\(restoreFocus, privacy: .public)")
        }
    }

    /// 导航到指定模块
    /// - Parameters:
    ///   - moduleID: 目标模块 ID
    ///   - context: 附加上下文
    public func navigate(to moduleID: String, context: [String: String] = [:]) {
        activeModuleID = moduleID
        query = context["query"] ?? ""
        syncPaletteMode(moduleID: moduleID, context: context)

        if !isVisible {
            show()
        }
    }

    /// 返回主搜索模式
    public func popToRoot() {
        activeModuleID = nil
        query = ""
        paletteMode.popToRoot()
    }

    /// 将协调器的模块状态同步到 PaletteMode
    ///
    /// 从 modules 中查找对应模块的元信息（名称、图标），一并写入 PaletteMode。
    private func syncPaletteMode(moduleID: String, context: [String: String] = [:]) {
        let module = modules.first { type(of: $0).id == moduleID }
        let name = module.map { type(of: $0).name } ?? moduleID
        let icon = module.map { type(of: $0).icon } ?? "questionmark"
        paletteMode.navigate(to: moduleID, name: name, icon: icon, context: context)
    }

    // MARK: - 搜索

    /// 单次搜索的结果上限
    ///
    /// 没有上限时，一个失控的模块会把几千条塞进 SwiftUI 列表、还要在主线程排序。
    private static let resultLimit = 60

    /// 单个模块的搜索超时
    ///
    /// 模块的 `searchItems` 跑在主 actor 上（协议本身是 `@MainActor`），
    /// 所以一个慢查询（EventKit、Spotlight、定位）会把**整批**结果卡住 ——
    /// 聚合是等所有模块都返回才结束的。超时之后放弃这个模块，
    /// 而不是让整块面板陪它等。
    private static let moduleTimeout = Duration.seconds(2)

    /// 聚合搜索：查询所有已启用模块
    ///
    /// - Parameter query: 搜索关键词
    /// - Returns: 去重、排序、限流之后的结果
    public func search(query: String) async -> [SearchableItem] {
        let enabledModules = modules.filter(\.isEnabled)

        let signpost = QuickLog.signposter(QuickLog.Category.palette)
        let interval = signpost.beginInterval("palette.search")
        let started = Date()

        let collected = await withTaskGroup(of: [SearchableItem].self) { group in
            for module in enabledModules {
                let moduleName = type(of: module).name
                group.addTask {
                    let items = await Self.search(module: module, query: query)
                    // 给每条搜索结果标注来源插件名
                    return items.map { $0.moduleName == nil ? $0.withModuleName(moduleName) : $0 }
                }
            }
            var results: [SearchableItem] = []
            for await items in group {
                results.append(contentsOf: items)
            }
            return results
        }

        // 去重：`SearchableItem` 的 `Hashable` 只看 id，而「id 以模块 id 开头」
        // 只是一条约定，没有任何东西在强制它。重复 id 会让 `ForEach` 进入未定义行为
        // （丢行、选中高亮错位），所以在这里挡一道。
        var seen = Set<String>()
        let deduped = collected.filter { seen.insert($0.id).inserted }

        // 排序：相关度降序，**同分时按 id 升序**。
        // 只按相关度排的话同分项的顺序由任务完成顺序决定，而常量相关度
        // （0.5 / 0.6 是常态）意味着同分是多数情况 —— 那等于没有顺序保证，
        // 列表每次刷新都可能换一个样子。
        let sorted = deduped.sorted {
            $0.relevance == $1.relevance ? $0.id < $1.id : $0.relevance > $1.relevance
        }

        let limited = Array(sorted.prefix(Self.resultLimit))

        signpost.endInterval("palette.search", interval)
        let elapsedMS = Date().timeIntervalSince(started) * 1000
        log.debug(
            """
            聚合搜索完成：\(enabledModules.count, privacy: .public) 个模块，\
            命中 \(collected.count, privacy: .public) 条 → \
            去重后 \(deduped.count, privacy: .public) 条 → \
            返回 \(limited.count, privacy: .public) 条，\
            耗时 \(elapsedMS, format: .fixed(precision: 1)) ms
            """)

        return limited
    }

    /// 查询单个模块，超时即放弃
    ///
    /// 竞速两个子任务：模块自己，和一个超时计时器。先完成的那个决定结果。
    /// 注意超时**不会**中断模块内部的同步工作（它在主 actor 上），
    /// 只是让我们不再等它 —— 这正是需要的：面板不能陪一个慢模块等下去。
    private static func search(module: any QuickModule, query: String) async -> [SearchableItem] {
        await withTaskGroup(of: [SearchableItem].self) { group in
            group.addTask { await module.searchItems(query: query) }
            group.addTask {
                try? await Task.sleep(for: Self.moduleTimeout)
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
            paletteMode: paletteMode,
            searchHandler: { [weak self] query in
                guard let self else { return [] }
                return await self.search(query: query)
            },
            moduleViewProvider: { [weak self] moduleID, context in
                guard let self else { return nil }
                return self.makeModuleView(moduleID: moduleID, context: context)
            }
        )
        let newPanel = PalettePanel(rootView: rootView)

        newPanel.onEscape = { [weak self] in
            guard let self else { return false }
            if self.activeModuleID != nil {
                self.popToRoot()
            } else {
                self.hide()
            }
            return true
        }

        newPanel.onDetach = { [weak self] in
            guard let self, let moduleID = self.activeModuleID else { return false }
            self.onDetach?(moduleID)
            return true
        }

        // 上下键与回车在 AppKit 层转给选中状态，见 PalettePanel.sendEvent 的说明
        newPanel.onMove = { [weak self] delta in
            self?.selection.move(delta) ?? false
        }
        newPanel.onSubmit = { [weak self] in
            self?.selection.activateSelection() ?? false
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
    /// 用户在点别处 —— 例如某个模块在启动时弹出的系统权限对话框也会抢走键盘焦点，
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

    /// 根据模块 ID 构建模块视图
    ///
    /// 通过闭包注入给 PaletteRootView，避免视图层直接依赖模块。
    private func makeModuleView(moduleID: String, context: [String: String]) -> AnyView? {
        guard let module = modules.first(where: { type(of: $0).id == moduleID }),
            module.isEnabled
        else {
            log.warning("找不到模块 \(moduleID, privacy: .public) 或模块已禁用")
            return nil
        }
        return module.makeView()
    }

    /// 将面板定位到光标所在屏幕的中上方
    private func positionOnCursorScreen() {
        guard let panel else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

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
