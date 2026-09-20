// TimestampConverterPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 时间戳转换器
///
/// 参考 Fasty timestamp-converter 布局：
/// 输入区 + 自动检测 → 结果卡片列表 → 底部当前时间
@MainActor
public final class TimestampConverterPlugin: QuickPlugin {

    public static let id = "timestamp-converter"
    public static let name = "时间戳转换"
    public static let icon = "clock"
    public static let triggerWords = ["时间戳", "timestamp", "unix", "时间转换", "日期"]

    public var isEnabled = true

    private let log = QuickLog.plugin(TimestampConverterPlugin.id)

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }
        return [
            SearchableItem(
                id: "timestamp-converter.open",
                pluginID: Self.id,
                title: Self.name,
                subtitle: "Unix 时间戳与日期互转",
                icon: Self.icon,
                relevance: 0.7,
                action: { EventBus.shared.post(NavigateEvent(pluginID: Self.id)) }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(TimestampConverterView())
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
