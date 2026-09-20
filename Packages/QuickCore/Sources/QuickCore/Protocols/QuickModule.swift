// QuickModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// Feature Module 的统一协议
///
/// 所有功能模块（Launcher、Clipboard、DevTools 等）都实现此协议。
/// AppCore 通过此协议发现、管理、路由模块。
/// 模块之间不直接依赖，仅通过 EventBus 通信。
@MainActor
public protocol QuickModule: AnyObject, Sendable {

    /// 模块唯一标识（全局唯一，用于事件路由和设置存储）
    static var id: String { get }

    /// 模块显示名称（出现在搜索结果和设置页面中）
    static var name: String { get }

    /// 模块图标（SF Symbol 名称）
    static var icon: String { get }

    /// 模块的触发词列表（中英双语）
    ///
    /// 用户在搜索框中输入这些词时会唤醒该模块。
    /// 同时展示在设置页面中，方便用户了解如何使用。
    static var triggerWords: [String] { get }

    /// 模块是否已启用
    var isEnabled: Bool { get set }

    /// 返回该模块能响应的搜索结果
    /// - Parameter query: 用户在搜索框中输入的文本
    /// - Returns: 匹配的搜索结果项
    func searchItems(query: String) async -> [SearchableItem]

    /// 构建模块的主视图（显示在面板中）
    func makeView() -> AnyView

    /// 构建模块的设置视图（显示在设置窗口中，无设置则返回 nil）
    func makeSettingsView() -> AnyView?

    /// 模块激活（应用启动或模块被启用时调用）
    func activate()

    /// 模块停用（应用退出或模块被禁用时调用）
    func deactivate()
}

// MARK: - 默认实现

public extension QuickModule {

    /// 默认启用
    var isEnabled: Bool {
        get { true }
        set {}
    }

    /// 默认无触发词
    static var triggerWords: [String] { [] }

    /// 默认无设置视图
    func makeSettingsView() -> AnyView? { nil }

    /// 默认空搜索结果
    func searchItems(query: String) async -> [SearchableItem] { [] }

    /// 默认无操作
    func activate() {}
    func deactivate() {}
}
