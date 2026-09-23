// SuperPanelRecentItem.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 工作台里「最近使用」的一行
///
/// 由宿主从 `UsageHistory` 的条目 id 解析出来：id 本身只有 `plugin.open.clipboard`、
/// `launcher.app.com.xxx` 这类形态，解析成标题与图标的知识只有组装层有，所以
/// 解析结果以本类型传进来，面板不认识插件与 AppIndex。
public struct SuperPanelRecentItem: Identifiable, Sendable, Hashable {

    public enum Kind: Sendable, Hashable {
        case app
        case plugin
        case command
    }

    public let id: String
    public let title: String
    public let subtitle: String?
    /// SF Symbol
    public let icon: String
    public let kind: Kind
    /// 跳转用的插件 id（`kind == .plugin`）
    public let pluginID: String?
    /// 启动用的应用路径（`kind == .app`）
    public let launchPath: String?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: String,
        kind: Kind,
        pluginID: String? = nil,
        launchPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.kind = kind
        self.pluginID = pluginID
        self.launchPath = launchPath
    }
}
