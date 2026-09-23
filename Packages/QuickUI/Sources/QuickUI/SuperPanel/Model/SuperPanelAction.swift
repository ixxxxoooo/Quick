// SuperPanelAction.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 超级面板里的一条可执行动作
///
/// 与 `SearchableItem` 分开：面板里的动作带序号、按键盘上下键选中、回车执行，
/// 语义是「对当前上下文做一件事」，不是「搜索结果」。
@MainActor
public struct SuperPanelAction: Identifiable {

    /// 稳定 id，用于选中态与去重
    public let id: String
    public let title: String
    public let subtitle: String
    /// SF Symbol
    public let icon: String
    /// 执行动作；由构建方负责发布事件、隐藏面板等副作用
    public let execute: () -> Void

    public init(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        execute: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.execute = execute
    }
}
