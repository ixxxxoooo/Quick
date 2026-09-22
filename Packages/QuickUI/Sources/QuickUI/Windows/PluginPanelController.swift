// PluginPanelController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
import QuickCore
import SwiftUI

/// 分离窗口控制器
///
/// 管理从面板中分离出来的独立插件窗口。每个插件最多一个分离窗口（单例策略），
/// 支持尺寸记忆。窗口控制（置顶 / 关闭）在**标题栏右侧**，所以分离窗口既没有系统红绿灯，
/// 也不需要在内容里再切一条工具栏。
///
/// 分离窗口与主面板是**两个互不相干的窗口**：唤出主面板不会把它带到前台，关掉主面板也不
/// 影响它。所以关闭 / 置顶这两个动作必须长在窗口自己身上 —— 用户不看着主面板时也得点得到。
///
/// **它的控制不使用悬浮胶囊**：胶囊是为「内容是一整块网页、没有任何自己的边框」的窗口准备的
/// （AI 网页窗口正是如此），而分离窗口本来就有一条自绘标题栏，控制放进标题栏比让用户去拖一个
/// 浮层自然。
@MainActor
public final class PluginPanelController {

    /// 一个分离窗口及其内容容器
    private struct DetachedWindow {
        let panel: DetachedPluginPanel
        /// 容器持有标题栏的置顶态，置顶变化时要让它重建根视图
        let container: DetachedWindowContainer
    }

    /// 已打开的分离窗口（pluginID -> 窗口）
    private var windows: [String: DetachedWindow] = [:]

    /// 重建插件视图的工厂（pluginID -> 视图提供者）
    ///
    /// 存的是工厂而不是建好的视图：刷新要能重新走一遍插件的
    /// `makePluginView()`，否则刷新只能重画一份旧状态。
    private var viewProviders: [String: () -> AnyView] = [:]

    /// 窗口关闭观察者（pluginID -> NSObjectProtocol）
    private var closeObservers: [String: NSObjectProtocol] = [:]

    private let log = QuickLog.ui

    /// 分离窗口尺寸存储键前缀
    private static let sizeKeyPrefix = "quick.detach.size."

    public init() {}

    // MARK: - 分离

    /// 分离插件到独立窗口
    ///
    /// - Parameters:
    ///   - pluginID: 插件 ID
    ///   - pluginName: 插件显示名称
    ///   - icon: 插件图标（SF Symbol）
    ///   - viewProvider: 视图工厂，每次「刷新」都会重新调用
    ///   - sourceWindow: 源面板窗口（用于计算偏移位置）
    public func detach(
        pluginID: String,
        pluginName: String,
        icon: String,
        viewProvider: @escaping () -> AnyView,
        sourceWindow: NSWindow?
    ) {
        if focusIfOpen(pluginID) {
            log.notice("插件 \(pluginID, privacy: .public) 分离窗口已存在，聚焦")
            return
        }

        viewProviders[pluginID] = viewProvider

        let savedSize = readSavedSize(for: pluginID)
        let width = savedSize?.width ?? DesignTokens.Size.detachedPanelDefaultWidth
        let height = savedSize?.height ?? DesignTokens.Size.detachedPanelDefaultHeight

        let panel = makeDetachedPanel(
            pluginID: pluginID,
            pluginName: pluginName,
            icon: icon,
            view: viewProvider(),
            width: width,
            height: height
        )

        positionRelativeTo(sourceWindow, window: panel)
        observeWindowClose(pluginID: pluginID, window: panel)

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        log.notice(
            """
            插件分离窗口已创建：\(pluginID, privacy: .public)，\
            尺寸 \(Int(width), privacy: .public)×\(Int(height), privacy: .public)
            """)
    }

    /// 聚焦已有的分离窗口
    @discardableResult
    public func focusIfOpen(_ pluginID: String) -> Bool {
        guard let window = windows[pluginID]?.panel, window.isVisible else {
            return false
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// 重建分离窗口里的插件视图（⌘R）
    public func refresh(_ pluginID: String) {
        guard let container = windows[pluginID]?.container,
            let provider = viewProviders[pluginID]
        else {
            log.warning("刷新失败：找不到插件 \(pluginID, privacy: .public) 的分离窗口")
            return
        }
        container.replacePluginView(with: provider())
        log.notice("已刷新插件分离窗口：\(pluginID, privacy: .public)")
    }

    /// 切换分离窗口置顶
    public func toggleAlwaysOnTop(_ pluginID: String) {
        guard let handle = windows[pluginID] else { return }
        setAlwaysOnTop(pluginID, isOn: handle.panel.level != .floating)
    }

    /// 设置分离窗口置顶
    public func setAlwaysOnTop(_ pluginID: String, isOn: Bool) {
        guard let handle = windows[pluginID] else { return }
        handle.panel.level = isOn ? .floating : .normal
        // 标题栏那颗按钮的激活态归视图管，容器重建一次根视图把它同步过去
        handle.container.setPinned(isOn)
    }

    /// 关闭指定插件的分离窗口
    public func close(_ pluginID: String) {
        guard let handle = windows[pluginID] else { return }
        saveWindowSize(pluginID: pluginID, window: handle.panel)
        handle.panel.onClose = nil
        handle.panel.close()
        cleanupWindow(pluginID: pluginID)
    }

    /// 关闭所有分离窗口
    public func closeAll() {
        for (pluginID, handle) in windows {
            saveWindowSize(pluginID: pluginID, window: handle.panel)
            handle.panel.onClose = nil
            handle.panel.close()
        }
        windows.removeAll()
        viewProviders.removeAll()
        for observer in closeObservers.values {
            NotificationCenter.default.removeObserver(observer)
        }
        closeObservers.removeAll()
        log.notice("所有分离窗口已关闭")
    }

    // MARK: - 窗口创建

    /// 创建分离窗口（NSPanel，无红绿灯，与主窗口同风格）
    private func makeDetachedPanel(
        pluginID: String,
        pluginName: String,
        icon: String,
        view: AnyView,
        width: CGFloat,
        height: CGFloat
    ) -> DetachedPluginPanel {
        let panel = DetachedPluginPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .fullSizeContentView, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = pluginName
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // 背景拖动只在「命中的那个视图肯让出按下事件」时才生效，SwiftUI 内容下靠不住：
        // 标题栏那块是显式的 `WindowDragArea`，两者是互补的，见它的说明。
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.level = .normal
        panel.animationBehavior = .documentWindow
        panel.isOpaque = false
        // 只有需要输入时才抢 key：唤出面板不该被分离窗口打断
        panel.becomesKeyOnlyIfNeeded = true
        panel.minSize = NSSize(
            width: DesignTokens.Size.detachedPanelMinWidth,
            height: DesignTokens.Size.detachedPanelMinHeight
        )
        panel.identifier = NSUserInterfaceItemIdentifier("quick.detach.\(pluginID)")

        // 标题栏右侧的置顶 / 关闭按钮长在面板自己身上（不再有悬浮胶囊）
        let container = DetachedWindowContainer(
            pluginName: pluginName,
            pluginIcon: icon,
            pluginView: view,
            onTogglePin: { [weak self] in
                self?.toggleAlwaysOnTop(pluginID)
            },
            onClose: { [weak self] in
                self?.close(pluginID)
            }
        )
        panel.contentView = container

        windows[pluginID] = DetachedWindow(panel: panel, container: container)

        panel.onClose = { [weak self] in
            self?.close(pluginID)
        }
        panel.onRefresh = { [weak self] in
            self?.refresh(pluginID)
        }

        return panel
    }

    /// 将分离窗口放到**鼠标所在的那块屏幕**上
    ///
    /// **不能用 `NSWindow.center()`。** 它落在主屏上，而主屏是系统设置里指定的那一块，
    /// 跟用户此刻在看哪块屏没有关系 —— 鼠标在内建屏上、主屏是外接显示器时，窗口就会
    /// 凭空跳到外接屏去。面板自己就是按鼠标所在屏定位的（`PaletteCoordinator`），
    /// 分离窗口必须落在同一块屏上，否则「从这里分离出来」这件事就断了。
    private func positionRelativeTo(_ sourceWindow: NSWindow?, window: NSWindow) {
        let screen =
            ScreenPlacement.screen() ?? sourceWindow?.screen ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            log.warning("找不到可用屏幕，分离窗口位置未调整")
            window.center()
            return
        }

        // 源窗口不在目标屏上时按「没有源窗口」处理：宁可居中，也不要贴着别的屏上的窗口放
        let sourceFrame = sourceWindow.flatMap { $0.screen === screen ? $0.frame : nil }
        window.setFrameOrigin(
            Self.detachedOrigin(
                size: window.frame.size,
                sourceFrame: sourceFrame,
                visibleFrame: screen.visibleFrame
            ))
        log.debug("分离窗口定位完成，屏幕=\(screen.localizedName, privacy: .public)")
    }

    /// 分离窗口的落点
    ///
    /// 抽成纯函数：两端（贴着源窗口时的越界、窗口比屏幕还大时的夹取）都只在这里出错，
    /// 而它们又只在特定的显示器摆法下才显形。
    ///
    /// - Parameters:
    ///   - size: 窗口尺寸
    ///   - sourceFrame: 源面板的 frame（已在目标屏上）；`nil` 表示没有源窗口，居中
    ///   - visibleFrame: 目标屏的可用区域
    /// - Returns: 窗口原点（全局坐标）
    static func detachedOrigin(
        size: CGSize,
        sourceFrame: NSRect?,
        visibleFrame: NSRect
    ) -> NSPoint {
        let origin: NSPoint
        if let sourceFrame {
            origin = NSPoint(
                x: sourceFrame.origin.x + detachOffset,
                y: sourceFrame.origin.y - detachOffset
            )
        } else {
            origin = NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            )
        }

        // 夹进这块屏：源窗口贴着边缘时那个 +30/-30 会把窗口推出去；
        // 窗口比屏幕还大时退化成「贴住最小边」，而不是让它跑到屏外看不见。
        let maxX = visibleFrame.maxX - size.width
        let maxY = visibleFrame.maxY - size.height
        return NSPoint(
            x: min(max(origin.x, visibleFrame.minX), max(maxX, visibleFrame.minX)),
            y: min(max(origin.y, visibleFrame.minY), max(maxY, visibleFrame.minY))
        )
    }

    /// 贴着源面板分离时的偏移量
    private static let detachOffset: CGFloat = 30

    // MARK: - 尺寸记忆

    private func saveWindowSize(pluginID: String, window: NSWindow) {
        let size = window.frame.size
        let dict: [String: CGFloat] = ["width": size.width, "height": size.height]
        UserDefaults.standard.set(dict, forKey: Self.sizeKeyPrefix + pluginID)
    }

    private func readSavedSize(for pluginID: String) -> NSSize? {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.sizeKeyPrefix + pluginID),
            let width = dict["width"] as? CGFloat, width > 0,
            let height = dict["height"] as? CGFloat, height > 0
        else {
            return nil
        }
        return NSSize(width: width, height: height)
    }

    // MARK: - 窗口生命周期

    private func observeWindowClose(pluginID: String, window: NSWindow) {
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            let closingWindow = notification.object as? NSWindow
            Task { @MainActor in
                guard let self,
                    let closingWindow,
                    closingWindow === self.windows[pluginID]?.panel
                else { return }
                self.saveWindowSize(pluginID: pluginID, window: closingWindow)
                self.cleanupWindow(pluginID: pluginID)
                self.log.notice("插件分离窗口已关闭：\(pluginID, privacy: .public)")
            }
        }
        closeObservers[pluginID] = observer
    }

    private func cleanupWindow(pluginID: String) {
        windows.removeValue(forKey: pluginID)
        viewProviders.removeValue(forKey: pluginID)
        if let observer = closeObservers.removeValue(forKey: pluginID) {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - 自定义分离面板（支持 Esc/⌘W 关闭、⌘R 刷新）

/// 分离插件的 NSPanel 子类
///
/// 无红绿灯、支持 Esc 关闭、⌘W 关闭、⌘R 刷新、可拖拽改变大小。
final class DetachedPluginPanel: NSPanel {

    var onClose: (() -> Void)?
    var onRefresh: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // Escape 关闭
            if Int(event.keyCode) == kVK_Escape {
                onClose?()
                return
            }
            if event.modifierFlags.contains(.command),
                let key = event.charactersIgnoringModifiers?.lowercased()
            {
                // ⌘W 关闭
                if key == "w" {
                    onClose?()
                    return
                }
                // ⌘R 刷新
                if key == "r" {
                    onRefresh?()
                    return
                }
            }
        }
        super.sendEvent(event)
    }
}

// MARK: - 分离窗口容器视图

/// 分离窗口的内容容器：插件视图铺满，悬浮胶囊叠在右上角
///
/// 分离窗口的内容容器
///
/// 只负责把 SwiftUI 根视图铺满，并把标题栏的置顶态传下去 —— 窗口控制长在标题栏里，
/// 所以这里不再叠任何浮层。
final class DetachedWindowContainer: NSView {

    private let hosting: NSHostingView<DetachedPanelContentView>
    private let pluginName: String
    private let pluginIcon: String
    private let onTogglePin: () -> Void
    private let onClose: () -> Void

    /// 当前置顶态（由控制器写入）
    private var isPinned = false

    init(
        pluginName: String,
        pluginIcon: String,
        pluginView: AnyView,
        onTogglePin: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.pluginName = pluginName
        self.pluginIcon = pluginIcon
        self.onTogglePin = onTogglePin
        self.onClose = onClose
        self.hosting = NSHostingView(
            rootView: DetachedPanelContentView(
                pluginName: pluginName,
                pluginIcon: pluginIcon,
                pluginView: pluginView,
                isPinned: false,
                onTogglePin: onTogglePin,
                onClose: onClose
            ))

        super.init(frame: .zero)

        hosting.wantsLayer = true
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    /// 用工厂新产出的视图替换内容（保留窗口本身与标题栏）
    func replacePluginView(with view: AnyView) {
        render(pluginView: view)
    }

    /// 同步置顶态到标题栏那颗按钮
    func setPinned(_ isPinned: Bool) {
        guard isPinned != self.isPinned else { return }
        self.isPinned = isPinned
        render(pluginView: hosting.rootView.pluginView)
    }

    /// 重建根视图
    private func render(pluginView: AnyView) {
        hosting.rootView = DetachedPanelContentView(
            pluginName: pluginName,
            pluginIcon: pluginIcon,
            pluginView: pluginView,
            isPinned: isPinned,
            onTogglePin: onTogglePin,
            onClose: onClose
        )
    }
}

// MARK: - 分离窗口内容视图

/// 分离窗口的根视图（与主窗口一致的外观）
///
/// 身份（图标 + 名称）与窗口控制（置顶 / 关闭）都在标题栏里，内容在下面铺满。
/// 标题栏本身仍是窗口的拖拽区（`isMovableByWindowBackground`）。
private struct DetachedPanelContentView: View {

    let pluginName: String
    let pluginIcon: String
    let pluginView: AnyView
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onClose: () -> Void

    /// 分离窗口没有头部搜索框，但插件视图可能用非可选的方式读这个环境；
    /// 给一份 `hasHeaderField = false` 的空对象，既避免取环境崩掉，也让插件知道这里没有搜索框。
    @State private var pluginSearch = PluginSearchQuery(hasHeaderField: false)

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            pluginView
                .environment(pluginSearch)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PaletteBackground())
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous))
    }

    /// 标题栏：左侧插件身份（整块可拖），右侧窗口控制
    private var titleBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // 身份区 + 中间空白整块都是拖拽区。拖拽区**不能铺到按钮上面** ——
            // 它是一个真实的 `NSView`，盖住按钮会把点击吃掉（见 `WindowDragArea`）。
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: pluginIcon)
                    .font(DesignTokens.Typography.inlineIcon)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                Text(pluginName)
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: DesignTokens.Spacing.md)
            }
            // 撑满标题栏高度，整条栏位都拖得动，而不是只有文字那一行
            .frame(maxHeight: .infinity)
            .background(WindowDragArea())

            BarButton(
                title: isPinned ? "取消窗口置顶" : "窗口置顶",
                icon: isPinned ? "pin.fill" : "pin",
                style: .icon,
                isActive: isPinned,
                action: onTogglePin
            )

            BarButton(
                title: "关闭窗口",
                icon: "xmark",
                style: .icon,
                tone: .destructive,
                action: onClose
            )
        }
        .padding(.leading, DesignTokens.Spacing.lg)
        .padding(.trailing, DesignTokens.Spacing.md)
        .frame(height: DesignTokens.Size.detachedTitleBarHeight)
    }
}

// MARK: - 标题栏拖拽区

/// 标题栏的拖拽区
///
/// **为什么需要它：** 窗口是不是「按背景拖动」，取决于 `hitTest` 命中的那个视图有没有
/// 返回 `mouseDownCanMoveWindow`，而面板里铺满的 vibrancy 背景（一个真实的
/// `NSVisualEffectView`）与 hosting view 都不返回 —— 于是 `isMovableByWindowBackground`
/// 在 SwiftUI 内容上靠不住，表现就是**窗口拖不动**。这里放一个只做一件事的 `NSView`：
/// 按下就 `performDrag`，不依赖上面那套判定。
///
/// 它只铺在标题栏的身份区与中间空白上，不盖住右上角的按钮 —— 它是个真实的 `NSView`，
/// 铺到按钮上面会把点击吃掉。
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragView { WindowDragView() }
    func updateNSView(_ nsView: WindowDragView, context: Context) {}
}

/// 拖拽区背后的视图
///
/// 独立类型而不是匿名内部类，是为了让测试能断言它真的挂上去了 ——
/// 「窗口拖不动」是个只能靠手试才发现的问题，值得一条结构性断言守着。
final class WindowDragView: NSView {

    /// 窗口没被激活时，第一次按下也要能拖起来
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
