// NetworkToolsModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 网络工具模块
///
/// IP 查询 + DNS 信息 + 网络测速。
/// 合并 Fasty 的 ip-query、dns-switch、speed-test。
@MainActor
public final class NetworkToolsModule: QuickModule {

    public static let id = "networktools"
    public static let name = "网络工具"
    public static let icon = "network"

    public var isEnabled = true

    private let log = QuickLog.module(NetworkToolsModule.id)

    private let service = NetworkService()

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        let triggers = ["ip", "网络", "network", "dns", "测速", "speed"]
        guard triggers.contains(where: { query.lowercased().contains($0) }) else { return [] }

        return [
            SearchableItem(
                id: "net.tools",
                moduleID: Self.id,
                title: "网络工具",
                subtitle: "IP 查询 / DNS / 测速",
                icon: "network",
                relevance: 0.6,
                action: {
                    EventBus.shared.post(NavigateEvent(moduleID: "networktools"))
                }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(NetworkToolsView(service: service))
    }

    public func activate() {
        log.notice("模块已激活")
    }

    public func deactivate() {
        log.notice("模块已停用")
    }
}
