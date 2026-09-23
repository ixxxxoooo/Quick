// SuperPanelQuickTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 工作台里的一张工具卡片
public struct SuperPanelQuickTool: Identifiable, Sendable, Hashable {

    /// 稳定 id（与插件 id 不必相同，用户配置里存的是它）
    public let id: String
    public let title: String
    /// SF Symbol
    public let icon: String
    /// 点击后跳转到的插件 id
    public let pluginID: String

    public init(id: String, title: String, icon: String, pluginID: String) {
        self.id = id
        self.title = title
        self.icon = icon
        self.pluginID = pluginID
    }
}

/// 工作台工具目录与用户配置的读写
public enum SuperPanelQuickTools {

    /// 默认可选工具目录（顺序即设置页下拉的顺序）
    public static let catalog: [SuperPanelQuickTool] = [
        SuperPanelQuickTool(id: "screenshot", title: "截图", icon: "camera", pluginID: "screenshot"),
        SuperPanelQuickTool(id: "clipboard", title: "剪贴板", icon: "doc.on.clipboard", pluginID: "clipboard"),
        SuperPanelQuickTool(
            id: "translator", title: "翻译", icon: "character.book.closed", pluginID: "translator"),
        SuperPanelQuickTool(id: "ai", title: "AI", icon: "sparkles", pluginID: "ai"),
        SuperPanelQuickTool(id: "notes", title: "备忘", icon: "text.page", pluginID: "notes"),
        SuperPanelQuickTool(
            id: "calculator", title: "计算", icon: "plus.forwardslash.minus", pluginID: "calculator"),
        SuperPanelQuickTool(id: "sysmonitor", title: "监控", icon: "cpu", pluginID: "sysmonitor"),
        SuperPanelQuickTool(id: "json", title: "JSON", icon: "curlybraces", pluginID: "json-formatter"),
        SuperPanelQuickTool(id: "calendar", title: "日历", icon: "calendar", pluginID: "calendar"),
        SuperPanelQuickTool(id: "filesearch", title: "文件", icon: "folder", pluginID: "filesearch"),
        SuperPanelQuickTool(id: "killprocess", title: "进程", icon: "xmark.app", pluginID: "killprocess"),
        SuperPanelQuickTool(id: "networktools", title: "网络", icon: "wifi", pluginID: "networktools"),
        SuperPanelQuickTool(id: "ocr", title: "识字", icon: "text.viewfinder", pluginID: "ocr"),
        SuperPanelQuickTool(id: "timestamp", title: "时间戳", icon: "clock", pluginID: "timestamp-converter"),
        SuperPanelQuickTool(id: "base64", title: "Base64", icon: "lock.doc", pluginID: "base64-codec"),
        SuperPanelQuickTool(id: "urlcodec", title: "URL", icon: "link", pluginID: "url-codec"),
        SuperPanelQuickTool(id: "uuid", title: "UUID", icon: "number", pluginID: "uuid-generator"),
        SuperPanelQuickTool(id: "hash", title: "Hash", icon: "number.square", pluginID: "hash-calculator"),
        SuperPanelQuickTool(id: "color", title: "颜色", icon: "paintpalette", pluginID: "color-compare"),
        SuperPanelQuickTool(
            id: "textdiff", title: "对比", icon: "arrow.left.arrow.right", pluginID: "text-diff"),
        SuperPanelQuickTool(
            id: "markdown", title: "Markdown", icon: "text.alignleft", pluginID: "markdown-preview"),
        SuperPanelQuickTool(id: "sql", title: "SQL", icon: "cylinder", pluginID: "sql-formatter")
    ]

    /// 默认常用工具（对齐 Fasty 的八宫格）
    public static let defaults: [SuperPanelQuickTool] = catalog.filter {
        ["screenshot", "clipboard", "translator", "ai", "notes", "calculator", "sysmonitor", "json"]
            .contains($0.id)
    }

    /// 从偏好读出用户配置的工具列表；没配过、或全都失效时回落到默认
    public static func load(from defaults: UserDefaults = .standard) -> [SuperPanelQuickTool] {
        guard let ids = defaults.stringArray(forKey: SuperPanelPreferences.Key.quickTools),
            !ids.isEmpty
        else {
            return Self.defaults
        }
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let resolved = ids.compactMap { byID[$0] }
        return resolved.isEmpty ? Self.defaults : resolved
    }

    /// 写回用户配置
    public static func save(_ tools: [SuperPanelQuickTool], to defaults: UserDefaults = .standard) {
        defaults.set(tools.map(\.id), forKey: SuperPanelPreferences.Key.quickTools)
    }

    /// 目录里尚未被加入的工具
    public static func available(excluding selected: [SuperPanelQuickTool]) -> [SuperPanelQuickTool] {
        let used = Set(selected.map(\.id))
        return catalog.filter { !used.contains($0.id) }
    }
}
