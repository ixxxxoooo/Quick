// SearchableItem.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 搜索结果的统一模型
///
/// 所有插件的搜索结果都封装为此类型，由面板统一展示。
/// 包含显示信息、相关度评分和执行动作。
public struct SearchableItem: Identifiable, Sendable {

    /// 结果唯一 ID
    public let id: String

    /// 来源插件 ID
    public let pluginID: String

    /// 来源插件显示名称（用于搜索结果右侧标注）
    public let pluginName: String?

    /// 显示标题
    public let title: String

    /// 副标题（可选，例如应用的路径或工具的描述）
    public let subtitle: String?

    /// 图标（SF Symbol 名称）
    public let icon: String

    /// 图标类型（用于区分 SF Symbol、应用图标、图片等）
    public let iconType: IconType

    /// 搜索相关度（0.0 ~ 1.0，越高越靠前）
    public let relevance: Double

    /// 快捷键提示（可选，例如 "⌘1"）
    public let shortcutHint: String?

    /// 执行动作（用户回车或点击时触发）
    public let action: @Sendable @MainActor () -> Void

    /// 图标类型枚举
    public enum IconType: Sendable {
        /// SF Symbol 图标
        case symbol
        /// 应用 Bundle 图标（值为 bundle path）
        case appIcon(String)
        /// 自定义图片（值为图片名或路径）
        case image(String)
    }

    /// 初始化搜索结果项
    /// - Parameters:
    ///   - id: 唯一标识
    ///   - pluginID: 来源插件标识
    ///   - pluginName: 来源插件显示名称（搜索结果右侧标注）
    ///   - title: 显示标题
    ///   - subtitle: 副标题
    ///   - icon: SF Symbol 名称
    ///   - iconType: 图标类型
    ///   - relevance: 相关度评分 (0.0~1.0)
    ///   - shortcutHint: 快捷键提示
    ///   - action: 执行动作
    public init(
        id: String,
        pluginID: String,
        pluginName: String? = nil,
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconType: IconType = .symbol,
        relevance: Double = 0.5,
        shortcutHint: String? = nil,
        action: @escaping @Sendable @MainActor () -> Void
    ) {
        self.id = id
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconType = iconType
        self.relevance = relevance
        self.shortcutHint = shortcutHint
        self.action = action
    }

    /// 返回一个新实例，换一个相关度
    ///
    /// 用于「同一条目在不同场景下权重不同」：例如首屏里的插件命令要排在应用之后，
    /// 而在按关键词搜索时它应该按自己的匹配分排。
    public func withRelevance(_ relevance: Double) -> SearchableItem {
        SearchableItem(
            id: id,
            pluginID: pluginID,
            pluginName: pluginName,
            title: title,
            subtitle: subtitle,
            icon: icon,
            iconType: iconType,
            relevance: relevance,
            shortcutHint: shortcutHint,
            action: action
        )
    }

    /// 返回一个新实例，填充 `pluginName`
    public func withPluginName(_ name: String) -> SearchableItem {
        SearchableItem(
            id: id,
            pluginID: pluginID,
            pluginName: name,
            title: title,
            subtitle: subtitle,
            icon: icon,
            iconType: iconType,
            relevance: relevance,
            shortcutHint: shortcutHint,
            action: action
        )
    }
}

// MARK: - Hashable（基于 id）

extension SearchableItem: Hashable {
    public static func == (lhs: SearchableItem, rhs: SearchableItem) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
