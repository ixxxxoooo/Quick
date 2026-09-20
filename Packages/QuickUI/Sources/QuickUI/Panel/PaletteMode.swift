// PaletteMode.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 面板的模式状态（搜索模式 vs 插件模式）
///
/// 这是 `PaletteCoordinator` 与 `PaletteRootView` 之间的桥接对象。
/// 协调器不能标记为 `@Observable`（会导致 AttributeGraph 死循环），
/// 但视图层需要响应模式切换。本对象只持有纯状态，不持有 `NSPanel` 或协调器，
/// 所以被 SwiftUI 观察是安全的。
@MainActor
@Observable
public final class PaletteMode {

    /// 当前活跃的插件 ID（nil 表示主搜索模式）
    public var activePluginID: String?

    /// 当前插件的上下文信息（键值对，插件自行解读）
    public var context: [String: String] = [:]

    /// 当前插件的显示名称（用于头部显示）
    public var activePluginName: String?

    /// 当前插件的图标（SF Symbol 名称）
    public var activePluginIcon: String?

    /// 是否处于插件模式
    public var isPluginMode: Bool { activePluginID != nil }

    public init() {}

    /// 导航到指定插件
    ///
    /// - Parameters:
    ///   - pluginID: 目标插件 ID
    ///   - name: 插件显示名称
    ///   - icon: 插件图标
    ///   - context: 附加上下文
    public func navigate(to pluginID: String, name: String, icon: String, context: [String: String] = [:]) {
        self.activePluginID = pluginID
        self.activePluginName = name
        self.activePluginIcon = icon
        self.context = context
    }

    /// 返回主搜索模式
    public func popToRoot() {
        activePluginID = nil
        activePluginName = nil
        activePluginIcon = nil
        context = [:]
    }
}
