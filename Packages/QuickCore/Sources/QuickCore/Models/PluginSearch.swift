// PluginSearch.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Observation

/// 插件模式下的「插件内搜索」桥接对象
///
/// 面板进入**声明了 `supportsPanelSearch`** 的插件后，头部原来的插件名位置换成搜索框，
/// 文本写在这里；插件视图通过 `@Environment(PluginSearchQuery.self)` 读取并自行过滤。
/// 它只持有纯状态、不持有任何窗口，所以被 SwiftUI 观察是安全的 —— 会与 AttributeGraph
/// 形成重建死循环的是持有 `NSPanel` 的协调器（见 `PaletteCoordinator` 顶部说明）。
///
/// **方向键与回车也必须有人接。** 搜索框拿到焦点后，field editor 会先把上下键拿去移动
/// 光标、把回车当成提交，插件列表一个键都收不到 —— 这正是主搜索踩过的坑。所以面板在
/// 插件模式下把键变成 `Navigation` 请求记在这里，插件用 `.onChange(of: commandToken)`
/// 取走并执行。
///
/// **为什么用「请求 + 令牌」而不是回调闭包：** 闭包要由插件视图在 `onAppear` 里挂上，
/// 而视图被重建时 `onDisappear` / `onAppear` 的先后顺序不保证 —— 后到的 `onDisappear`
/// 会把新视图刚挂上的回调清掉，表现就是「方向键时灵时不灵」。令牌只有单调递增，
/// 放和收互不干扰。
///
/// 不声明搜索的插件拿不到这个环境（`@Environment` 取值是 `nil`）。
@MainActor
@Observable
public final class PluginSearchQuery {

    /// 搜索框里的文本
    public var text: String = ""

    /// 插件当前是否要吃上下 / 左右 / 回车
    ///
    /// 由插件视图按自己的状态维护：剪贴板列表始终要；JSON 只在树视图要（代码视图要留给
    /// 编辑器的光标与换行）。面板据此决定是消费按键还是放行走响应链。
    public var wantsNavigation = false

    /// 导航请求类型
    public enum Navigation: Sendable, Equatable {
        /// 上下移动（`-1` 上、`+1` 下）
        case move(Int)
        /// 左右切换（`-1` 左、`+1` 右）
        case tab(Int)
        /// 回车
        case submit
    }

    /// 最近一次导航请求
    public private(set) var lastCommand: Navigation?

    /// 请求序号：每次 `request` 递增，插件用 `.onChange(of:)` 监听它
    public private(set) var commandToken = 0

    /// 面板头部是否真的有一个搜索框绑着它
    ///
    /// 分离窗口也会注入一份空对象兜底（免得插件用非可选方式取环境时崩掉），
    /// 但那里没有搜索框。插件据此决定「要不要自己抢焦点、自己收键」。
    public let hasHeaderField: Bool

    public init(hasHeaderField: Bool = true) {
        self.hasHeaderField = hasHeaderField
    }

    /// 请求把焦点交给头部搜索框的序号
    ///
    /// 头部搜索框**默认不聚焦**（进入插件时焦点属于插件视图），按 ⌘F 时由宿主递增它，
    /// 搜索框用 `.onChange(of:)` 收到后自己取焦点 —— 焦点在 `SearchFieldView` 内部，
    /// 外部只能这样请求，不能直接设。
    public private(set) var focusToken = 0

    /// 请求把焦点交给头部搜索框
    public func requestFocus() {
        focusToken &+= 1
    }

    /// 记下一次导航请求
    public func request(_ command: Navigation) {
        lastCommand = command
        commandToken &+= 1
    }

    /// 清空文本与导航状态
    ///
    /// 进入 / 离开插件时必须调：留在 `wantsNavigation = true` 上，下一个插件会莫名其妙地
    /// 吃掉方向键。
    public func reset() {
        text = ""
        wantsNavigation = false
        lastCommand = nil
    }
}
