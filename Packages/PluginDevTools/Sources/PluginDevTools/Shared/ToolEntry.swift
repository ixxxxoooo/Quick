// ToolEntry.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 子工具统一入口模型
///
/// DevTools 插件内部的每个子工具都实现此协议，
/// 由 DevToolsPlugin 统一注册和路由。
@MainActor
protocol DevTool {
    /// 工具唯一标识
    var id: String { get }
    /// 工具显示名称
    var name: String { get }
    /// 工具图标（SF Symbol）
    var icon: String { get }
    /// 搜索关键词
    var keywords: [String] { get }
    /// 工具描述
    var description: String { get }
    /// 工具视图
    func makeView() -> AnyView
}

/// 子工具条目（用于搜索和展示）
struct ToolEntryInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let icon: String
    let description: String
}
