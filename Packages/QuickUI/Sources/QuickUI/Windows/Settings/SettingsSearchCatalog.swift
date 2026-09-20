// SettingsSearchCatalog.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 侧边栏搜索的一条结果
struct SettingsSearchEntry: Identifiable, Hashable {

    /// 稳定标识
    let id: String

    /// 命中项所在的分栏
    let tab: SettingsTab

    /// 命中项的标题
    let title: String

    /// 所在分组的名字，让用户知道它是干什么的
    let subtitle: String?
}

/// 设置项索引
///
/// **手写清单，不自动扫描视图树。** SwiftUI 的视图树扫不出来，而这份清单只有
/// 几十行；新增一项设置时忘了登记，改这里比引入一套反射便宜得多。
/// 这是有意的取舍，不是遗漏。
enum SettingsSearchCatalog {

    /// 静态条目（模块与权限那两类是动态生成的）
    private static let staticEntries: [SettingsSearchEntry] = [
        .init(id: "general.launchAtLogin", tab: .general, title: "开机自动启动", subtitle: "启动"),
        .init(id: "general.hotkey", tab: .general, title: "全局快捷键", subtitle: "唤出"),
        .init(id: "general.close", tab: .general, title: "关闭面板", subtitle: "唤出"),
        .init(id: "modules", tab: .modules, title: "模块开关", subtitle: "模块"),
        .init(id: "permissions", tab: .permissions, title: "系统权限", subtitle: "权限"),
        .init(id: "about.version", tab: .about, title: "版本", subtitle: "关于"),
        .init(id: "about.bundle", tab: .about, title: "Bundle ID", subtitle: "关于"),
        .init(id: "about.panel", tab: .about, title: "面板尺寸", subtitle: "面板"),
        .init(id: "about.hotkey", tab: .about, title: "全局快捷键", subtitle: "面板"),
        .init(id: "about.logs", tab: .about, title: "查看实时日志", subtitle: "排查")
    ]

    /// 按关键词搜索
    ///
    /// 标题与副标题都参与匹配，所以「权限」「辅助功能」「定位」都能命中。
    ///
    /// - Parameters:
    ///   - query: 搜索词
    ///   - modules: 当前模块清单（动态生成模块条目用）
    /// - Returns: 命中的条目，空查询返回空
    static func results(for query: String, modules: [SettingsModule]) -> [SettingsSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let dynamicEntries: [SettingsSearchEntry] =
            modules.map {
                SettingsSearchEntry(id: "module.\($0.id)", tab: .modules, title: $0.name, subtitle: "模块")
            }
            + SettingsPermission.allCases.map {
                SettingsSearchEntry(
                    id: "permission.\($0.rawValue)", tab: .permissions, title: $0.title, subtitle: "权限")
            }

        return (staticEntries + dynamicEntries).filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.subtitle?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }
}
