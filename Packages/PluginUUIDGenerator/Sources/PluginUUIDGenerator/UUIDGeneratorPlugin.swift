// UUIDGeneratorPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 批量生成 UUID / GUID 插件
///
/// 参考 Fasty uuid-generator 布局：
/// 工具栏（数量/大写/去连字符 + 生成按钮）→ 结果列表 → 状态栏
@MainActor
public final class UUIDGeneratorPlugin: QuickPlugin {

    public static let id = "uuid-generator"
    public static let name = "UUID 生成器"
    public static let icon = "number"
    public static let triggerWords = ["uuid", "guid", "生成", "随机", "唯一标识"]

    public var isEnabled = true

    private let log = QuickLog.plugin(UUIDGeneratorPlugin.id)

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }
        return [
            SearchableItem(
                id: "uuid-generator.open",
                pluginID: Self.id,
                title: Self.name,
                subtitle: "批量生成 UUID / GUID",
                icon: Self.icon,
                relevance: 0.7,
                action: { EventBus.shared.post(NavigateEvent(pluginID: Self.id)) }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(UUIDGeneratorView())
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
