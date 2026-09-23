// CommandDescriptor.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一条可被搜索、可被快捷键唤醒的命令
///
/// 描述符不含闭包，可以放进快照、跨线程打分。真正执行时宿主按 `id` 回到插件的
/// `perform(commandID:)`。`id` 一旦发布就不能改，它是快捷键和「是否打开」的主键。
public struct CommandDescriptor: Sendable, Hashable, Identifiable {

    /// 稳定主键，例如 `systemcontrol.lock`、`plugin.open.clipboard`
    public let id: String

    /// 所属插件；宿主命令用 `core`
    public let pluginID: String

    /// 所属插件的显示名，快捷键列表右侧用它
    public let pluginName: String

    /// 命令标题
    public let title: String

    /// 补充说明
    public let subtitle: String?

    /// 搜索词。标题和插件名之外还想被命中的说法放这里
    public let keywords: [String]

    /// SF Symbol
    public let icon: String

    /// 空查询时是否作为该插件的那一条入口
    ///
    /// 每个插件最多露出一条，由索引按声明顺序取第一条为真的。
    public let showsWhenQueryEmpty: Bool

    /// 别名在设置里的键；没有别名的命令留空
    public let aliasKey: String?

    /// 初始化一条命令
    public init(
        id: String,
        pluginID: String,
        pluginName: String,
        title: String,
        subtitle: String? = nil,
        keywords: [String] = [],
        icon: String,
        showsWhenQueryEmpty: Bool = false,
        aliasKey: String? = nil
    ) {
        self.id = id
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.icon = icon
        self.showsWhenQueryEmpty = showsWhenQueryEmpty
        self.aliasKey = aliasKey
    }

    /// 换一份关键词，其余字段不动
    ///
    /// 别名是用户后加的，建索引时拼进去，不改插件声明的那一份。
    public func replacingKeywords(_ keywords: [String]) -> CommandDescriptor {
        CommandDescriptor(
            id: id,
            pluginID: pluginID,
            pluginName: pluginName,
            title: title,
            subtitle: subtitle,
            keywords: keywords,
            icon: icon,
            showsWhenQueryEmpty: showsWhenQueryEmpty,
            aliasKey: aliasKey
        )
    }

    /// 用插件元信息合成「打开该插件」
    public static func openPlugin(
        id pluginID: String,
        name: String,
        icon: String,
        keywords: [String],
        subtitle: String? = nil
    ) -> CommandDescriptor {
        CommandDescriptor(
            id: CommandID.openPlugin(pluginID),
            pluginID: pluginID,
            pluginName: name,
            title: name,
            subtitle: subtitle,
            keywords: keywords,
            icon: icon,
            showsWhenQueryEmpty: true
        )
    }
}

/// 命令 id 的拼法
///
/// 集中在这里，是为了热键迁移、搜索和执行三处不会各写各的前缀。
public enum CommandID {

    /// 唤出或隐藏主面板
    public static let togglePalette = "core.togglePalette"

    /// 唤出或隐藏超级面板
    ///
    /// 超级面板是宿主组件而不是插件，所以用 `core` 前缀。它**不进主搜索的命令目录** ——
    /// 只在热键注册与设置页里用得到，能被搜到反而是多出来的入口。
    public static let superPanel = "core.superPanel"

    /// 打开某个插件的面板
    public static func openPlugin(_ pluginID: String) -> String {
        "plugin.open.\(pluginID)"
    }

    /// 从「打开插件」命令里取出插件 id；不是这种命令时返回 nil
    public static func openedPluginID(in commandID: String) -> String? {
        let prefix = "plugin.open."
        guard commandID.hasPrefix(prefix) else { return nil }
        let pluginID = String(commandID.dropFirst(prefix.count))
        return pluginID.isEmpty ? nil : pluginID
    }

    /// 系统操作。`raw` 是 `SystemAction.rawValue`，发布后不能改
    public static func systemAction(_ raw: String) -> String {
        "systemcontrol.\(raw)"
    }

    /// 启动某个应用。Bundle ID 本身带点，所以前缀必须整段匹配
    public static func launchApp(_ bundleID: String) -> String {
        "launcher.app.\(bundleID)"
    }

    /// 运行一条用户保存的终端命令
    public static func shell(_ uuid: String) -> String {
        "launcher.shell.\(uuid.lowercased())"
    }

    /// 应用启动命令的前缀
    public static let launchAppPrefix = "launcher.app."

    /// 终端命令的前缀
    public static let shellPrefix = "launcher.shell."
}
