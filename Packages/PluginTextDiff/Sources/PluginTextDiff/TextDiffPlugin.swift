// TextDiffPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 文本对比工具
///
/// 参考 Fasty text-diff 布局：
/// 工具栏（互换/复制/清空 + 差异统计）→ 左右双栏编辑区 → 差异结果
@MainActor
public final class TextDiffPlugin: QuickPlugin {

    public static let id = "text-diff"
    public static let name = "文本对比"
    public static let icon = "doc.on.doc"
    public static let triggerWords = ["diff", "对比", "比较", "差异", "text diff"]

    public var isEnabled = true

    private let log = QuickLog.plugin(TextDiffPlugin.id)

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }
        return [
            SearchableItem(
                id: "text-diff.open",
                pluginID: Self.id,
                title: Self.name,
                subtitle: "左右双栏对比文本差异",
                icon: Self.icon,
                relevance: 0.7,
                action: { EventBus.shared.post(NavigateEvent(pluginID: Self.id)) }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(TextDiffView())
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
