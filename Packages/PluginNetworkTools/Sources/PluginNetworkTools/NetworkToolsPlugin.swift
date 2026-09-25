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
public final class NetworkToolsPlugin: QuickPlugin, PluginViewProviding, PluginSettingsProviding {

    public static let id = "networktools"
    public static let name = "网络工具"
    public static let icon = "wifi"
    public static let description = "网络环境与连通性检测，支持本机局域网 IP 查询、当前公共外网 IP 识别与 DNS 服务解析。"
    public static let triggerWords = ["ip", "内网ip", "外网ip", "localip", "publicip", "network", "dns", "测速", "speedtest"]

    public var isEnabled = true

    private let log = QuickLog.plugin(NetworkToolsPlugin.id)

    private let service = NetworkService()

    public init() {}

    public func makeView() -> AnyView {
        AnyView(NetworkToolsView(service: service))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(NetworkToolsSettingsView())
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
