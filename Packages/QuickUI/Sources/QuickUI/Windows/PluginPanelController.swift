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
/// 支持尺寸记忆。窗口控制（关闭 / 刷新 / 置顶）全部由右上角的悬浮胶囊承担，
/// 所以分离窗口既没有系统红绿灯，也不需要在内容里再切一条工具栏。
///
/// 分离窗口与主面板是**两个互不相干的窗口**：唤出主面板不会把它们带到前台，
/// 关掉主面板也不会影响它们。这也正是胶囊必须存在的理由 —— 用户不看着主面板时，
/// 关闭 / 刷新 / 置顶这三个动作得有个地方可点。
@MainActor
public final class PluginPanelController {

    /// 一个分离窗口及其悬浮胶囊
    private struct DetachedWindow {
        let panel: DetachedPluginPanel
        let capsule: FloatingCapsuleView
    }

    /// 已打开的分离窗口（pluginID -> 窗口）
    private var windows: [String: DetachedWindow] = [:]

    /// 重建插件视图的工厂（pluginID -> 视图提供者）
    ///
    /// 存的是工厂而不是建好的视图：胶囊的「刷新」要能重新走一遍插件的
    /// `makePluginView()`，否则刷新只能重画一份旧状态。
    private var viewProviders: [String: () -> AnyView] = [:]

    /// 窗口关闭观察者（pluginID -> NSObjectProtocol）
    private var closeObservers: [String: NSObjectProtocol] = [:]

    private let log = QuickLog.ui

    /// 分离窗口尺寸存储键前缀
    private static let sizeKeyPrefix = "quick.detach.size."

    /// 胶囊里置顶按钮的标识
    private static let pinActionID = "pin"

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

    /// 重建分离窗口里的插件视图（胶囊的刷新按钮 / ⌘R）
    public func refresh(_ pluginID: String) {
        guard let container = windows[pluginID]?.panel.contentView as? DetachedWindowContainer,
            let provider = viewProviders[pluginID]
        else {
            log.warning("刷新失败：找不到插件 \(pluginID, privacy: .public) 的分离窗口")
            return
        }
        container.replacePluginView(with: provider())
        log.notice("已刷新插件分离窗口：\(pluginID, privacy: .public)")
    }

    /// 设置分离窗口置顶
    public func setAlwaysOnTop(_ pluginID: String, isOn: Bool) {
        guard let handle = windows[pluginID] else { return }
        handle.panel.level = isOn ? .floating : .normal
        handle.capsule.setToggle(
            Self.pinActionID,
            isOn: isOn,
            tooltip: isOn ? "取消置顶" : "窗口置顶"
        )
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

        // 悬浮胶囊：窗口控制都在这里
        let capsule = FloatingCapsuleView(
            positionKey: "detach.\(pluginID)",
            actions: [
                CapsuleAction(
                    id: Self.pinActionID,
                    symbol: "pin",
                    tooltip: "窗口置顶",
                    kind: .toggle
                ) { [weak self] in
                    guard let self, let handle = self.windows[pluginID] else { return }
                    self.setAlwaysOnTop(pluginID, isOn: handle.panel.level != .floating)
                },
                CapsuleAction(
                    id: "refresh",
                    symbol: "arrow.clockwise",
                    tooltip: "刷新插件视图 (⌘R)"
                ) { [weak self] in
                    self?.refresh(pluginID)
                },
                CapsuleAction(
                    id: "close",
                    symbol: "xmark",
                    tooltip: "关闭窗口 (⌘W / Esc)",
                    kind: .destructive
                ) { [weak self] in
                    self?.close(pluginID)
                }
            ]
        )

        let container = DetachedWindowContainer(
            pluginName: pluginName,
            pluginIcon: icon,
            pluginView: view,
            capsule: capsule
        )
        panel.contentView = container

        windows[pluginID] = DetachedWindow(panel: panel, capsule: capsule)
        capsule.positionInSuperview()

        panel.onClose = { [weak self] in
            self?.close(pluginID)
        }
        panel.onRefresh = { [weak self] in
            self?.refresh(pluginID)
        }

        return panel
    }

    /// 将分离窗口定位到源面板附近（偏移 +30, -30）
    private func positionRelativeTo(_ sourceWindow: NSWindow?, window: NSWindow) {
        if let source = sourceWindow {
            let origin = source.frame.origin
            window.setFrameOrigin(
                NSPoint(
                    x: origin.x + 30,
                    y: origin.y - 30
                ))
        } else {
            window.center()
        }
    }

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
/// 胶囊必须**叠**在内容之上而不是挤进布局：插件视图自己并不知道头顶多了个控件，
/// 叠放才能保证「随便哪个插件都能拿到窗口控制」，而不是只有留了白的插件才行。
final class DetachedWindowContainer: NSView {

    private let hosting: NSHostingView<DetachedPanelContentView>
    private let pluginName: String
    private let pluginIcon: String

    init(
        pluginName: String,
        pluginIcon: String,
        pluginView: AnyView,
        capsule: FloatingCapsuleView
    ) {
        self.pluginName = pluginName
        self.pluginIcon = pluginIcon
        self.hosting = NSHostingView(
            rootView: DetachedPanelContentView(
                pluginName: pluginName,
                pluginIcon: pluginIcon,
                pluginView: pluginView
            ))

        super.init(frame: .zero)

        hosting.wantsLayer = true
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        addSubview(capsule)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    /// 用工厂新产出的视图替换内容（保留胶囊与窗口本身）
    func replacePluginView(with view: AnyView) {
        hosting.rootView = DetachedPanelContentView(
            pluginName: pluginName,
            pluginIcon: pluginIcon,
            pluginView: view
        )
    }
}

// MARK: - 分离窗口内容视图

/// 分离窗口的根视图（与主窗口一致的外观）
///
/// 只承载身份（图标 + 名称）与内容 —— 置顶 / 刷新 / 关闭都在悬浮胶囊里。
/// 标题栏本身仍是窗口的拖拽区（`isMovableByWindowBackground`）。
private struct DetachedPanelContentView: View {

    let pluginName: String
    let pluginIcon: String
    let pluginView: AnyView

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            pluginView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PaletteBackground())
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous))
    }

    /// 标题栏：只放插件身份，窗口控制交给悬浮胶囊
    private var titleBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: pluginIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(pluginName)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.leading, DesignTokens.Spacing.lg)
        // 右侧让开胶囊：标题不会被它压住
        .padding(.trailing, DesignTokens.Size.capsuleReservedWidth)
        .frame(height: DesignTokens.Size.detachedTitleBarHeight)
    }
}
