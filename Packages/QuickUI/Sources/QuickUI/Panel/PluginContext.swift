// PluginContext.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 插件导航上下文的 Environment 键
///
/// 面板从搜索模式切换到插件模式时，可能携带初始内容（例如粘贴检测到 JSON 后
/// 自动跳转到格式化插件，同时把文本一并带过去）。插件视图通过 `@Environment`
/// 读取这个值，而不需要认识 `PaletteMode` 或 `PaletteCoordinator`。
private struct PluginContextKey: EnvironmentKey {
    static let defaultValue: [String: String] = [:]
}

public extension EnvironmentValues {
    /// 导航到此插件时附带的上下文键值对
    ///
    /// 常见键：
    /// - `"query"`: 初始输入文本（如粘贴检测到的 JSON/SQL）
    var pluginContext: [String: String] {
        get { self[PluginContextKey.self] }
        set { self[PluginContextKey.self] = newValue }
    }
}
