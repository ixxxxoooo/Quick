// JSONFormatterPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// JSON 格式化插件
///
/// 参考 Fasty json-formatter 布局：
/// 工具栏（格式化/压缩/复制/清空 + 缩进选择）→ 编辑区 → 状态栏
@MainActor
public final class JSONFormatterPlugin: QuickPlugin, PluginViewProviding, PluginSettingsProviding {

    public static let id = "json-formatter"
    public static let name = "JSON 格式化"
    public static let icon = "curlybraces"
    public static let description = "JSON 语法校验、层级高亮、格式化美化与单行紧凑压缩，支持缩进空格调整与一键复制。"
    public static let triggerWords = ["json", "format", "jsonformat", "jsonmin", "unescape", "jsonunescape"]

    /// 面板头部保留搜索框：树视图里用它定位字段
    public static var supportsPanelSearch: Bool { true }

    public var isEnabled = true

    private let log = QuickLog.plugin(JSONFormatterPlugin.id)

    public init() {}

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(JSONFormatterView(buffer: buffer))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(JSONFormatterSettingsView())
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
