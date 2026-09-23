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
public final class JSONFormatterPlugin: QuickPlugin {

    public static let id = "json-formatter"
    public static let name = "JSON 格式化"
    public static let icon = "curlybraces"
    public static let description = "JSON 语法校验、层级高亮、格式化美化与单行紧凑压缩，支持缩进空格调整与一键复制。"
    public static let triggerWords = ["JSON 格式化", "json", "格式化", "format"]

    /// 面板头部保留搜索框：树视图里用它定位字段
    public static var supportsPanelSearch: Bool { true }

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "json-formatter.format", pluginID: id, pluginName: name, title: "JSON 格式化",
                subtitle: "缩进并美化 JSON", keywords: ["json格式化", "格式化json", "jsonformat"],
                icon: "curlybraces"),
            CommandDescriptor(
                id: "json-formatter.minify", pluginID: id, pluginName: name, title: "JSON 压缩",
                subtitle: "压成单行、去掉空白", keywords: ["json压缩", "压缩json", "jsonmin"],
                icon: "arrow.down.right.and.arrow.up.left"),
            CommandDescriptor(
                id: "json-formatter.unescape", pluginID: id, pluginName: name, title: "JSON 去转义",
                subtitle: "把转义后的 JSON 字符串还原", keywords: ["json去转义", "jsonunescape"],
                icon: "textformat")
        ]
    }

    public var isEnabled = true

    private let log = QuickLog.plugin(JSONFormatterPlugin.id)

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }
        return [
            SearchableItem(
                id: "json-formatter.open",
                pluginID: Self.id,
                title: Self.name,
                subtitle: "格式化/压缩 JSON，语法高亮",
                icon: Self.icon,
                relevance: 0.7,
                action: { EventBus.shared.post(NavigateEvent(pluginID: Self.id)) }
            )
        ]
    }

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(JSONFormatterView(buffer: buffer))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
