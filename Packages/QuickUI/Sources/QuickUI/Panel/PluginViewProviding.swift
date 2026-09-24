// PluginViewProviding.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 插件为自己的面板提供根视图
///
/// 与 `QuickPlugin` 分开是为了让 `QuickCore` 不必认识 SwiftUI：核心协议只描述
/// 「有哪些命令、怎么搜索、怎么执行」，视图属于 UI 层的能力。
///
/// **宿主通过 `as?` 运行时查询，不实现时面板会是空白** —— 所以
/// `PaletteCoordinator.makePluginView` 在查询失败时必须打 `.warning`，
/// 否则「插件忘了实现这个协议」会表现成「面板坏了」而没有任何线索。
@MainActor
public protocol PluginViewProviding {

    /// 构建插件的主视图（显示在面板中）
    func makeView() -> AnyView
}

/// 插件为自己的设置页提供内容
///
/// 分离的理由与 `PluginViewProviding` 相同。返回 nil 表示这个插件没有专属设置页，
/// 由 `FeatureSettingsPane` 渲染默认的三段式布局。
@MainActor
public protocol PluginSettingsProviding {

    /// 构建插件的设置视图（显示在设置窗口中，无设置则返回 nil）
    func makeSettingsView() -> AnyView?
}

// MARK: - 默认实现

public extension PluginSettingsProviding {

    /// 默认无设置视图：设置页只显示概览与触发关键字
    func makeSettingsView() -> AnyView? { nil }
}
