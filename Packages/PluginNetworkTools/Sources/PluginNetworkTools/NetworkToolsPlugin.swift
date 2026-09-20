// NetworkToolsPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 网络工具插件
///
/// IP 查询 + DNS 信息 + 网络测速。
/// 合并 Fasty 的 ip-query、dns-switch、speed-test。
@MainActor
public final class NetworkToolsPlugin: QuickPlugin {

    public static let id = "networktools"
    public static let name = "网络工具"
    public static let icon = "network"
    public static let triggerWords = ["ip", "网络", "network", "dns", "测速", "speed"]

    public var isEnabled = true

    private let log = QuickLog.plugin(NetworkToolsPlugin.id)

    private let service = NetworkService()

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        // 用整词匹配而不是 contains：否则 clipboard / multiply / description 都会误触发本插件
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }

        return [
            SearchableItem(
                id: "networktools.tools",
                pluginID: Self.id,
                title: "网络工具",
                subtitle: "IP 查询 / DNS / 测速",
                icon: "network",
                relevance: 0.6,
                action: {
                    EventBus.shared.post(NavigateEvent(pluginID: "networktools"))
                }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(NetworkToolsView(service: service))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
