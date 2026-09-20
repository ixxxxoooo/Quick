// QuickPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// Feature Plugin 的统一协议
///
/// 所有功能插件（Launcher、Clipboard、DevTools 等）都实现此协议。
/// AppCore 通过此协议发现、管理、路由插件。
/// 插件之间不直接依赖，仅通过 EventBus 通信。
@MainActor
public protocol QuickPlugin: AnyObject, Sendable {

    /// 插件唯一标识（全局唯一，用于事件路由和设置存储）
    static var id: String { get }

    /// 插件显示名称（出现在搜索结果和设置页面中）
    static var name: String { get }

    /// 插件图标（SF Symbol 名称）
    static var icon: String { get }

    /// 插件的触发词列表（中英双语）
    ///
    /// 用户在搜索框中输入这些词时会唤醒该插件。
    /// 同时展示在设置页面中，方便用户了解如何使用。
    static var triggerWords: [String] { get }

    /// 插件是否已启用
    var isEnabled: Bool { get set }

    /// 返回该插件能响应的搜索结果
    /// - Parameter query: 用户在搜索框中输入的文本
    /// - Returns: 匹配的搜索结果项
    func searchItems(query: String) async -> [SearchableItem]

    /// 构建插件的主视图（显示在面板中）
    func makeView() -> AnyView

    /// 构建插件的设置视图（显示在设置窗口中，无设置则返回 nil）
    func makeSettingsView() -> AnyView?

    /// 插件激活（应用启动或插件被启用时调用）
    func activate()

    /// 插件停用（应用退出或插件被禁用时调用）
    func deactivate()
}

// MARK: - 默认实现

public extension QuickPlugin {

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
