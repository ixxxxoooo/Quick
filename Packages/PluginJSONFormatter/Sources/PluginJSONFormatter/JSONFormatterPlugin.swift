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
    public static let triggerWords = ["json", "格式化", "美化", "json formatter", "json格式化"]

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

    public func makeView() -> AnyView {
        AnyView(JSONFormatterView())
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
