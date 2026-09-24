// PaletteHostSearchSource.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore

/// 宿主自己的一个搜索来源
///
/// 用来承接**不属于任何插件**的搜索结果。文件搜索是第一个：它由 `QuickPlatform`
/// 提供能力，装配在 `AppCore` 里，没有插件身份 —— 因此不出现在插件列表、
/// 不能被单独禁用，也没有自己的面板。
///
/// 之所以做成协议而不是让引擎直接认识文件搜索：`QuickUI` 不该 import
/// `QuickPlatform`，更不该认识 Spotlight。引擎只认「一个能按查询给结果的来源」。
@MainActor
public protocol PaletteHostSearchSource: Sendable {

    /// 来源标识，用于日志与结果项的 `pluginID`
    nonisolated var sourceID: String { get }

    /// 结果行右侧显示的名字
    nonisolated var displayName: String { get }

    /// 这个来源要不要处理这次查询
    ///
    /// 必须便宜：它在每次按键上都会跑。
    func accepts(query: String) -> Bool

    /// 按查询现算结果
    ///
    /// 与插件的 `dynamicSearch` 同样要求：循环里看 `Task.isCancelled`，
    /// 新的一次按键会取消上一次。
    func search(query: String) async -> [SearchableItem]
}
