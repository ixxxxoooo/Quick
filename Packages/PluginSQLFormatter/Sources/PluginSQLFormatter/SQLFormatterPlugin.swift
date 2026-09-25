// SQLFormatterPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// SQL 格式化插件
///
/// 参考 Fasty sql-formatter 布局：
/// 工具栏（格式化/压缩/复制/清空 + 方言/缩进选择）→ 编辑区 → 状态栏
@MainActor
public final class SQLFormatterPlugin: QuickPlugin, PluginViewProviding, PluginSettingsProviding {

    public static let id = "sql-formatter"
    public static let name = "SQL 格式化"
    public static let icon = "cylinder.fill"
    public static let description = "SQL 查询语句美化排版与单行压缩，支持关键字大小写规范化与自定义缩进风格。"
    public static let triggerWords = ["sql", "mysql", "sqlformat", "sqlmin"]

    public var isEnabled = true

    private let log = QuickLog.plugin(SQLFormatterPlugin.id)

    public init() {}

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(SQLFormatterView(buffer: buffer))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(SQLFormatterSettingsView())
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
