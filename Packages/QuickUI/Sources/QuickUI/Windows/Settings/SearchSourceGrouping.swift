// SearchSourceGrouping.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 「搜索」设置页里搜索来源的分类
///
/// 19 个插件 + 文件搜索平铺成一长列开关，既难找又没人会逐个动它。按用途分成几组、默认折叠，
/// 组标题上写着「已开 / 总数」，需要时再展开。
///
/// 纯值逻辑，不依赖 SwiftUI，可脱离界面单测。认不出的 id 一律进「其他」，不会丢项。
public enum SearchSourceCategory: String, CaseIterable, Sendable, Identifiable {
    case system
    case productivity
    case developer
    case other

    public var id: String { rawValue }

    /// 组标题
    public var title: String {
        switch self {
        case .system: "应用与系统"
        case .productivity: "效率"
        case .developer: "开发者工具"
        case .other: "其他"
        }
    }

    /// 来源 id → 分类
    ///
    /// id 与 `SettingsTab.pluginID` 保持一致；文件搜索是宿主来源（`filesearch`），归到系统组。
    public static func category(forSourceID id: String) -> SearchSourceCategory {
        switch id {
        case "launcher", "systemcontrol", "sysmonitor", "killprocess", "networktools", "filesearch":
            .system
        case "clipboard", "calculator", "calendar", "screenshot", "translator", "ai":
            .productivity
        case "json-formatter", "sql-formatter", "base64-codec", "url-codec",
            "uuid-generator", "hash-calculator", "timestamp-converter", "text-diff":
            .developer
        default:
            .other
        }
    }
}

/// 一组搜索来源
public struct SearchSourceGroup: Identifiable, Sendable {
    public let category: SearchSourceCategory
    public let sources: [SettingsSearchSource]

    public var id: String { category.id }

    /// 组内当前已开启的数量（`enabledOverrides` 优先于来源自带的状态）
    public func enabledCount(overrides: [String: Bool] = [:]) -> Int {
        sources.filter { overrides[$0.id] ?? $0.isEnabled }.count
    }
}

extension SearchSourceGroup {

    /// 把来源按分类分组：保持分类的固定顺序与组内原顺序，空组不出现
    public static func grouping(_ sources: [SettingsSearchSource]) -> [SearchSourceGroup] {
        let buckets = Dictionary(grouping: sources) { SearchSourceCategory.category(forSourceID: $0.id) }
        return SearchSourceCategory.allCases.compactMap { category in
            guard let members = buckets[category], !members.isEmpty else { return nil }
            return SearchSourceGroup(category: category, sources: members)
        }
    }
}
