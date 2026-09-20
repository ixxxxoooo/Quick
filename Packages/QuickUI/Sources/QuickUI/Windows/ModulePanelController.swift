// ModulePanelController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 分离窗口控制器
///
/// 管理从面板中分离出来的独立模块窗口。
/// 每个模块最多一个分离窗口（单例策略），支持尺寸记忆。
@MainActor
public final class ModulePanelController {

    /// 已打开的分离窗口（moduleID -> NSWindow）
    private var detachedWindows: [String: NSWindow] = [:]

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
        let width = savedSize?.width ?? DesignTokens.Size.detachedPanelDefaultWidth
        let height = savedSize?.height ?? DesignTokens.Size.detachedPanelDefaultHeight

        let window = makeDetachedWindow(
            moduleID: moduleID,
            moduleName: moduleName,
            icon: icon,
            view: view,
            width: width,
            height: height
        )

        positionRelativeTo(sourceWindow, window: window)

        detachedWindows[moduleID] = window
        observeWindowClose(moduleID: moduleID, window: window)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        log.notice(
            """
            模块分离窗口已创建：\(moduleID, privacy: .public)，\
            尺寸 \(Int(width), privacy: .public)×\(Int(height), privacy: .public)
            """)
    }

    /// 聚焦已有的分离窗口
    ///
    /// - Parameter moduleID: 模块 ID
    /// - Returns: 是否成功聚焦（窗口存在返回 true）
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

    /// 创建分离窗口
    private func makeDetachedWindow(
        moduleID: String,
        moduleName: String,
        icon: String,
        view: AnyView,
        width: CGFloat,
        height: CGFloat
    ) -> NSWindow {
        let contentView = DetachedPanelContentView(
            moduleName: moduleName,
            moduleIcon: icon,
            moduleView: view,
            onClose: { [weak self] in
                self?.close(moduleID)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = moduleName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(
            width: DesignTokens.Size.detachedPanelMinWidth,
            height: DesignTokens.Size.detachedPanelMinHeight
        )
        window.animationBehavior = .documentWindow
        window.identifier = NSUserInterfaceItemIdentifier("quick.detach.\(moduleID)")

        let hosting = NSHostingView(rootView: contentView)
        hosting.wantsLayer = true
        window.contentView = hosting

        return window
    }

    /// 将分离窗口定位到源面板附近（偏移 +20, -20）
    private func positionRelativeTo(_ sourceWindow: NSWindow?, window: NSWindow) {
        if let source = sourceWindow {
            let origin = source.frame.origin
            window.setFrameOrigin(
                NSPoint(
                    x: origin.x + 20,
                    y: origin.y - 20
                ))
        } else {
            window.center()
        }
    }

    // MARK: - 尺寸记忆

    /// 保存窗口尺寸
    private func saveWindowSize(moduleID: String, window: NSWindow) {
        let size = window.frame.size
        let dict: [String: CGFloat] = ["width": size.width, "height": size.height]
        UserDefaults.standard.set(dict, forKey: Self.sizeKeyPrefix + moduleID)
    }

    /// 读取保存的窗口尺寸
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

    /// 监听窗口关闭通知
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

    /// 清理已关闭窗口的引用
    private func cleanupWindow(moduleID: String) {
        detachedWindows.removeValue(forKey: moduleID)
        if let observer = closeObservers.removeValue(forKey: moduleID) {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - 分离窗口内容视图

/// 分离窗口的根视图
///
/// 包含自定义标题栏（模块名 + 关闭按钮）和模块视图内容。
private struct DetachedPanelContentView: View {

    let moduleName: String
    let moduleIcon: String
    let moduleView: AnyView
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            moduleView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.ultraThinMaterial)
    }

    /// 自定义标题栏
    private var titleBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: moduleIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(moduleName)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .frame(height: DesignTokens.Size.detachedTitleBarHeight)
    }
}
