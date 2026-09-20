// ModulePanelController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
import QuickCore
import SwiftUI

/// 分离窗口控制器
///
/// 管理从面板中分离出来的独立模块窗口。
/// 每个模块最多一个分离窗口（单例策略），支持尺寸记忆。
/// 分离窗口与主窗口保持一致外观（无红绿灯、毛玻璃背景、圆角）。
@MainActor
public final class ModulePanelController {

    /// 已打开的分离窗口（moduleID -> NSPanel）
    private var detachedWindows: [String: NSPanel] = [:]

    /// 窗口关闭观察者（moduleID -> NSObjectProtocol）
    private var closeObservers: [String: NSObjectProtocol] = [:]

    private let log = QuickLog.ui

    /// 分离窗口尺寸存储键前缀
    private static let sizeKeyPrefix = "quick.detach.size."

    public init() {}

    /// 分离模块到独立窗口
    ///
    /// - Parameters:
    ///   - moduleID: 模块 ID
    ///   - moduleName: 模块显示名称
    ///   - icon: 模块图标（SF Symbol）
    ///   - view: 模块视图
    ///   - sourceWindow: 源面板窗口（用于计算偏移位置）
    public func detach(
        moduleID: String,
        moduleName: String,
        icon: String,
        view: AnyView,
        sourceWindow: NSWindow?
    ) {
        if focusIfOpen(moduleID) {
            log.notice("模块 \(moduleID, privacy: .public) 分离窗口已存在，聚焦")
            return
        }

        let savedSize = readSavedSize(for: moduleID)
        let width = savedSize?.width ?? DesignTokens.Size.panelWidth
        let height = savedSize?.height ?? DesignTokens.Size.panelHeight

        let panel = makeDetachedPanel(
            moduleID: moduleID,
            moduleName: moduleName,
            icon: icon,
            view: view,
            width: width,
            height: height
        )

        positionRelativeTo(sourceWindow, window: panel)

        detachedWindows[moduleID] = panel
        observeWindowClose(moduleID: moduleID, window: panel)

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        log.notice(
            """
            模块分离窗口已创建：\(moduleID, privacy: .public)，\
            尺寸 \(Int(width), privacy: .public)×\(Int(height), privacy: .public)
            """)
    }

    /// 聚焦已有的分离窗口
    @discardableResult
    public func focusIfOpen(_ moduleID: String) -> Bool {
        guard let window = detachedWindows[moduleID], window.isVisible else {
            return false
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// 关闭指定模块的分离窗口
    public func close(_ moduleID: String) {
        guard let window = detachedWindows[moduleID] else { return }
        saveWindowSize(moduleID: moduleID, window: window)
        window.close()
        cleanupWindow(moduleID: moduleID)
    }

    /// 关闭所有分离窗口
    public func closeAll() {
        for (moduleID, window) in detachedWindows {
            saveWindowSize(moduleID: moduleID, window: window)
            window.close()
        }
        detachedWindows.removeAll()
        for observer in closeObservers.values {
            NotificationCenter.default.removeObserver(observer)
        }
        closeObservers.removeAll()
        log.notice("所有分离窗口已关闭")
    }

    // MARK: - 窗口创建

    /// 创建分离窗口（NSPanel，无红绿灯，与主窗口同风格）
    private func makeDetachedPanel(
        moduleID: String,
        moduleName: String,
        icon: String,
        view: AnyView,
        width: CGFloat,
        height: CGFloat
    ) -> NSPanel {
        let panel = DetachedModulePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .fullSizeContentView, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = moduleName
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
        panel.minSize = NSSize(
            width: DesignTokens.Size.detachedPanelMinWidth,
            height: DesignTokens.Size.detachedPanelMinHeight
        )
        panel.identifier = NSUserInterfaceItemIdentifier("quick.detach.\(moduleID)")

        let contentView = DetachedPanelContentView(
            moduleName: moduleName,
            moduleIcon: icon,
            moduleView: view,
            isPinned: false,
            onClose: { [weak self] in
                self?.close(moduleID)
            },
            onPin: { [weak panel] isPinned in
                panel?.level = isPinned ? .floating : .normal
            }
        )

        let hosting = NSHostingView(rootView: contentView)
        hosting.wantsLayer = true
        panel.contentView = hosting

        // 配置 Escape 和 ⌘W 关闭
        panel.onEscape = { [weak self] in
            self?.close(moduleID)
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

    private func saveWindowSize(moduleID: String, window: NSWindow) {
        let size = window.frame.size
        let dict: [String: CGFloat] = ["width": size.width, "height": size.height]
        UserDefaults.standard.set(dict, forKey: Self.sizeKeyPrefix + moduleID)
    }

    private func readSavedSize(for moduleID: String) -> NSSize? {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.sizeKeyPrefix + moduleID),
            let width = dict["width"] as? CGFloat, width > 0,
            let height = dict["height"] as? CGFloat, height > 0
        else {
            return nil
        }
        return NSSize(width: width, height: height)
    }

    // MARK: - 窗口生命周期

    private func observeWindowClose(moduleID: String, window: NSWindow) {
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            let closingWindow = notification.object as? NSWindow
            Task { @MainActor in
                guard let self,
                    let closingWindow,
                    closingWindow === self.detachedWindows[moduleID]
                else { return }
                self.saveWindowSize(moduleID: moduleID, window: closingWindow)
                self.cleanupWindow(moduleID: moduleID)
                self.log.notice("模块分离窗口已关闭：\(moduleID, privacy: .public)")
            }
        }
        closeObservers[moduleID] = observer
    }

    private func cleanupWindow(moduleID: String) {
        detachedWindows.removeValue(forKey: moduleID)
        if let observer = closeObservers.removeValue(forKey: moduleID) {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - 自定义分离面板（支持 Esc/⌘W 关闭和拖拽调整）

/// 分离模块的 NSPanel 子类
///
/// 无红绿灯、支持 Esc 关闭、⌘W 关闭、可拖拽改变大小。
final class DetachedModulePanel: NSPanel {

    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // Escape 关闭
            if Int(event.keyCode) == kVK_Escape {
                onEscape?()
                return
            }
            // ⌘W 关闭
            if event.modifierFlags.contains(.command),
                event.charactersIgnoringModifiers?.lowercased() == "w"
            {
                onEscape?()
                return
            }
        }
        super.sendEvent(event)
    }
}

// MARK: - 分离窗口内容视图

/// 分离窗口的根视图（与主窗口一致的外观）
private struct DetachedPanelContentView: View {

    let moduleName: String
    let moduleIcon: String
    let moduleView: AnyView
    @State var isPinned: Bool
    let onClose: () -> Void
    let onPin: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 自定义标题栏（可拖拽区域）
            titleBar

            // 模块内容
            moduleView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PaletteBackground())
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous))
    }

    /// 自定义标题栏
    private var titleBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: moduleIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(moduleName)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)

            Spacer()

            // 置顶按钮
            Button {
                isPinned.toggle()
                onPin(isPinned)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundStyle(isPinned ? Color.accentColor : DesignTokens.Colors.textTertiary)
                    .rotationEffect(.degrees(isPinned ? 0 : 45))
            }
            .buttonStyle(.plain)
            .help(isPinned ? "取消置顶" : "窗口置顶")

            // 关闭按钮
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("关闭 (⌘W / Esc)")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(height: DesignTokens.Size.detachedTitleBarHeight)
    }
}
