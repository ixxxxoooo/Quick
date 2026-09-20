// PaletteMode.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 面板的模式状态（搜索模式 vs 模块模式）
///
/// 这是 `PaletteCoordinator` 与 `PaletteRootView` 之间的桥接对象。
/// 协调器不能标记为 `@Observable`（会导致 AttributeGraph 死循环），
/// 但视图层需要响应模式切换。本对象只持有纯状态，不持有 `NSPanel` 或协调器，
/// 所以被 SwiftUI 观察是安全的。
@MainActor
@Observable
public final class PaletteMode {

    /// 当前活跃的模块 ID（nil 表示主搜索模式）
    public var activeModuleID: String?

    /// 当前模块的上下文信息（键值对，模块自行解读）
    public var context: [String: String] = [:]

    /// 当前模块的显示名称（用于头部显示）
    public var activeModuleName: String?

    /// 当前模块的图标（SF Symbol 名称）
    public var activeModuleIcon: String?

    /// 是否处于模块模式
    public var isModuleMode: Bool { activeModuleID != nil }

    public init() {}

    /// 导航到指定模块
    ///
    /// - Parameters:
    ///   - moduleID: 目标模块 ID
    ///   - name: 模块显示名称
    ///   - icon: 模块图标
    ///   - context: 附加上下文
    public func navigate(to moduleID: String, name: String, icon: String, context: [String: String] = [:]) {
        self.activeModuleID = moduleID
        self.activeModuleName = name
        self.activeModuleIcon = icon
        self.context = context
    }

    /// 返回主搜索模式
    public func popToRoot() {
        activeModuleID = nil
        activeModuleName = nil
        activeModuleIcon = nil
        context = [:]
    }
}
