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

    /// 这个插件自己那份数据库 schema
    ///
    /// 只有需要真表的插件才要实现它（剪贴板历史、笔记、片段这类要排序和过滤的
    /// 数据）。用键值存零散状态的插件留空即可。
    ///
    /// 表结构归插件自己所有：宿主不预先建任何插件表，也不读插件表。迁移 id 一旦
    /// 发布就不能改，它是「这段 DDL 跑过没有」的唯一判据。
    static var storageMigrations: [SQLiteMigration] { get }
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

    /// 默认不建表：只有用真表的插件才声明 schema
    static var storageMigrations: [SQLiteMigration] { [] }
}
