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
@MainActor
@Observable
public final class PaletteCoordinator {

    /// 当前活跃的模块 ID（nil 表示主搜索模式）
    public private(set) var activeModuleID: String?

    /// 面板是否可见
    public var isVisible: Bool { panel?.isVisible ?? false }

    /// 搜索文本（双向绑定到搜索框）
    public var query: String = ""

    /// 被面板遮挡前的前台应用（用于恢复焦点）
    private var previousApp: NSRunningApplication?

    /// 面板实例（延迟创建）
    private var panel: PalettePanel?

    /// 所有已注册模块（由 AppCore 注入）
    private var modules: [any QuickModule] = []

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
        }

        previousApp = NSWorkspace.shared.frontmostApplication
        ensurePanel()
        positionOnCursorScreen()
        panel?.makeKeyAndOrderFront(nil)
    }

    /// 隐藏面板
    /// - Parameter restoreFocus: 是否恢复之前应用的焦点
    public func hide(restoreFocus: Bool = true) {
        panel?.orderOut(nil)

        if restoreFocus, let app = previousApp, !app.isTerminated {
            app.activate()
        }
        previousApp = nil
    }

    /// 导航到指定模块
    /// - Parameters:
    ///   - moduleID: 目标模块 ID
    ///   - context: 附加上下文
    public func navigate(to moduleID: String, context: [String: String] = [:]) {
        activeModuleID = moduleID
        query = context["query"] ?? ""

        if !isVisible {
            show()
        }
    }

    /// 返回主搜索模式
    public func popToRoot() {
        activeModuleID = nil
        query = ""
    }

    // MARK: - 搜索

    /// 聚合搜索：并发查询所有已启用模块
    /// - Parameter query: 搜索关键词
    /// - Returns: 排序后的搜索结果
    public func search(query: String) async -> [SearchableItem] {
        let enabledModules = modules.filter(\.isEnabled)

        return await withTaskGroup(of: [SearchableItem].self) { group in
            for module in enabledModules {
                group.addTask {
                    await module.searchItems(query: query)
                }
            }
            var results: [SearchableItem] = []
            for await items in group {
                results.append(contentsOf: items)
            }
            return results.sorted { $0.relevance > $1.relevance }
        }
    }

    // MARK: - 内部方法

    /// 确保面板已创建
    private func ensurePanel() {
        guard panel == nil else { return }
        let rootView = PaletteRootView(coordinator: self)
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

        panel = newPanel
    }

    /// 将面板定位到光标所在屏幕的中上方
    private func positionOnCursorScreen() {
        guard let panel else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return }

        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.maxY - panelSize.height - screenFrame.height * DesignTokens.Size.paletteTopMarginFraction

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
