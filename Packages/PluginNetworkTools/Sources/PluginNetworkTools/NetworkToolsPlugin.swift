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
public final class NetworkToolsPlugin: QuickPlugin, PluginViewProviding {

    public static let id = "networktools"
    public static let name = "网络工具"
    public static let icon = "wifi"
    public static let description = "网络环境与连通性检测，支持本机局域网 IP 查询、当前公共外网 IP 识别与 DNS 服务解析。"
    public static let triggerWords = ["IP 查询", "ip", "网络", "network", "dns", "测速", "speed", "查询", "地址"]

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "networktools.localIP", pluginID: id, pluginName: name, title: "本机 IP",
                subtitle: "查看本机内网地址", keywords: ["本机ip", "内网ip"], icon: "network"),
            CommandDescriptor(
                id: "networktools.publicIP", pluginID: id, pluginName: name, title: "公网 IP",
                subtitle: "查询当前公网出口地址", keywords: ["公网ip", "外网ip", "publicip"],
                icon: "globe"),
            CommandDescriptor(
                id: "networktools.dns", pluginID: id, pluginName: name, title: "DNS",
                subtitle: "查看当前 DNS 服务器", keywords: ["dns", "dns服务器"],
                icon: "server.rack"),
            CommandDescriptor(
                id: "networktools.speed", pluginID: id, pluginName: name, title: "测速",
                subtitle: "测试网络速度", keywords: ["测速", "speedtest"], icon: "speedometer")
        ]
    }

    public var isEnabled = true

    private let log = QuickLog.plugin(NetworkToolsPlugin.id)

    private let service = NetworkService()

    public init() {}

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
