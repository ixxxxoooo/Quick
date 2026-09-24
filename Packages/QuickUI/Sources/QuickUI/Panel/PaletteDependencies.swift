// PaletteDependencies.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 面板协调器的外部依赖，由宿主一次性注入
///
/// 这些闭包原先都是 `PaletteCoordinator` 上的 `public var`，谁都可以在任意时刻改写。
/// 后果是「初始化顺序」变成隐式契约：漏设一个不报错，只是静默降级 ——
/// `isSearchSourceEnabled` 的默认值是 `{ _ in true }`，忘了设就等于放行了所有插件。
///
/// 收到一个不可变结构里之后，缺哪一项是**编译错误**，而不是运行时的行为差异。
/// 变更时机也从「任意时刻」收窄到 `PaletteCoordinator.attach(_:)` 一次。
@MainActor
public struct PaletteDependencies {

    /// 某个插件是否参与主搜索。关闭后不调用它的动态搜索，静态命令也不进快照
    public let isSearchSourceEnabled: (String) -> Bool

    /// 命中静态命令时的执行入口
    ///
    /// `@Sendable`：它会被存进 `SearchableItem.action`，而那个结构是 `Sendable`。
    public let invokeCommand: @MainActor @Sendable (String) -> Void

    /// 把当前插件分离成独立窗口
    public let onDetach: (String) -> Void

    /// 面板即将显示（宿主用它做强制键盘布局这类事）
    public let onPanelWillShow: () -> Void

    /// 面板已经隐藏
    public let onPanelDidHide: () -> Void

    /// 最近使用。首屏顺序依赖它，所以是宿主级的：应用、命令、工具条目在同一张表里
    public let usageHistory: UsageHistory?

    /// 构造依赖
    /// - Parameters:
    ///   - isSearchSourceEnabled: 插件是否参与主搜索
    ///   - invokeCommand: 命令执行入口
    ///   - onDetach: 分离插件面板
    ///   - onPanelWillShow: 面板即将显示
    ///   - onPanelDidHide: 面板已经隐藏
    ///   - usageHistory: 最近使用存储；没有时传 nil，首屏就不会按最近使用提权
    public init(
        isSearchSourceEnabled: @escaping (String) -> Bool,
        invokeCommand: @escaping @MainActor @Sendable (String) -> Void,
        onDetach: @escaping (String) -> Void,
        onPanelWillShow: @escaping () -> Void,
        onPanelDidHide: @escaping () -> Void,
        usageHistory: UsageHistory?
    ) {
        self.isSearchSourceEnabled = isSearchSourceEnabled
        self.invokeCommand = invokeCommand
        self.onDetach = onDetach
        self.onPanelWillShow = onPanelWillShow
        self.onPanelDidHide = onPanelDidHide
        self.usageHistory = usageHistory
    }
}
