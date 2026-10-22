// SettingsSidebarItem.swift
// Quick — 原生 macOS 效率启动器
// @author ixxxxoooo

import Foundation

/// 侧栏的一行：分区标题，或可选中的页面入口
enum SettingsSidebarItem: Equatable {
    case header(String)
    case page(id: String, tab: SettingsTab, title: String, subtitle: String?)

    var tab: SettingsTab? {
        if case .page(_, let tab, _, _) = self { return tab }
        return nil
    }

    /// 分区列表：宿主页面 → 核心功能（应用启动器） → 插件 → 关于
    /// - Parameter plugins: 已按名称排好序的插件清单
    /// - Returns: 平铺的行列表
    static func browse(plugins: [SettingsPlugin]) -> [SettingsSidebarItem] {
        func page(_ tab: SettingsTab, _ title: String? = nil) -> SettingsSidebarItem {
            .page(id: tab.rawValue, tab: tab, title: title ?? tab.title, subtitle: nil)
        }
        var items = SettingsSection.host.tabs.map { page($0) }
        if let launcher = plugins.first(where: { $0.id == "launcher" }),
            let tab = SettingsTab.tab(forPluginID: "launcher")
        {
            items.append(.header("核心功能"))
            items.append(page(tab, launcher.name))
        }
        items.append(.header("插件"))
        for plugin in plugins where plugin.id != "launcher" {
            if let tab = SettingsTab.tab(forPluginID: plugin.id) { items.append(page(tab, plugin.name)) }
        }
        items.append(.header(""))
        items.append(page(.about))
        return items
    }

    /// 搜索结果列表
    static func results(_ entries: [SettingsSearchEntry]) -> [SettingsSidebarItem] {
        [.header("搜索结果")]
            + entries.map { .page(id: $0.id, tab: $0.tab, title: $0.title, subtitle: $0.subtitle) }
    }
}
