// QuickPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// Feature Plugin 的统一协议
///
/// 所有功能插件（Launcher、Clipboard、DevTools 等）都实现此协议。
/// AppCore 通过此协议发现、管理、路由插件。
/// 插件之间不直接依赖，仅通过 EventBus 通信。
@MainActor
public protocol QuickPlugin: AnyObject, Sendable {

    /// 插件唯一标识（全局唯一，用于事件路由和设置存储）
    static var id: String { get }

    /// 插件显示名称（出现在搜索结果和设置页面中）
    static var name: String { get }

    /// 插件图标（SF Symbol 名称）
    static var icon: String { get }

    /// 插件功能说明与使用指南
    static var description: String { get }

    /// 插件的触发词列表（中英双语）
    ///
    /// 用户在搜索框中输入这些词时会唤醒该插件。
    /// 一条命令可以有多个关键字；不同关键字可以打开同一个插件里的不同功能。
    /// 精确匹配到两条时不执行，避免猜错。
    static var triggerWords: [String] { get }

    /// 插件是否已启用
    var isEnabled: Bool { get set }

    /// 面板模式下是否在头部保留一个「插件内搜索」框
    ///
    /// 默认 false：不声明的插件进入面板后，头部仍然只有 返回 / 名称 / 分离。
    /// 声明为 true 的插件（剪贴板、JSON 格式化等）会得到搜索框，文本经
    /// `PluginSearchQuery` 环境对象传进来，由插件自己决定怎么过滤。
    /// **默认不聚焦**，按 ⌘F 才把焦点放进去。
    static var supportsPanelSearch: Bool { get }

    /// 返回该插件能响应的搜索结果
    /// - Parameter query: 用户在搜索框中输入的文本
    /// - Returns: 匹配的搜索结果项
    func searchItems(query: String) async -> [SearchableItem]

    /// 构建插件的主视图（显示在面板中）
    func makeView() -> AnyView

    /// 构建插件的设置视图（显示在设置窗口中，无设置则返回 nil）
    func makeSettingsView() -> AnyView?

    /// 插件激活（应用启动或插件被启用时调用）
    func activate()

    /// 插件停用（应用退出或插件被禁用时调用）
    func deactivate()

    /// 首屏（空查询）时想展示的条目
    ///
    /// 首屏不该只有应用 —— 用户也想直接看到插件的命令。默认实现取「触发词裸查询的第一条」，
    /// 于是绝大多数插件（每个开发者工具、翻译、OCR……）自动获得一个入口，不必各写一遍。
    ///
    /// **只取一条**是有意的：一个插件在首屏铺开一屏结果会把它变成插件自己的列表页。
    /// 想给首屏一组精选条目的插件可以覆盖它。
    func defaultItems() async -> [SearchableItem]

    /// 这个插件声明的静态命令
    ///
    /// 默认是一条「打开本插件」。结果会随输入变化的插件改走 `dynamicSearch`，
    /// 并把这里留空或只放不会重复的入口。命令 id 一旦发布就不能改。
    static var commands: [CommandDescriptor] { get }

    /// 这次查询要不要走动态搜索
    ///
    /// 返回 false 时聚合器不会调用 `dynamicSearch`。闸门必须便宜：
    /// 它在每次按键、每个已启用插件上都会跑。
    func accepts(query: String) -> Bool

    /// 按查询现算的结果
    ///
    /// 只在 `accepts` 为真时调用。循环里要看 `Task.isCancelled`，新的一次按键会取消上一次。
    func dynamicSearch(query: String) async -> [SearchableItem]

    /// 执行一条命令
    ///
    /// 热键和搜索命中的是同一个 id。命令已关闭时宿主不会调用这里。
    func perform(commandID: String)

    /// 这个插件自己那份数据库 schema
    ///
    /// 只有需要真表的插件才要实现它（剪贴板历史、笔记、片段这类要排序和过滤的
    /// 数据）。用键值存零散状态的插件留空即可。
    ///
    /// 表结构归插件自己所有：宿主不预先建任何插件表，也不读插件表。迁移 id 一旦
    /// 发布就不能改，它是「这段 DDL 跑过没有」的唯一判据。
    static var storageMigrations: [SQLiteMigration] { get }
}

// MARK: - 默认实现

public extension QuickPlugin {

    /// 默认启用
    var isEnabled: Bool {
        get { true }
        set {}
    }

    /// 默认无触发词
    static var triggerWords: [String] { [] }

    /// 默认不在面板里提供插件内搜索
    static var supportsPanelSearch: Bool { false }

    /// 默认无功能说明
    static var description: String { "" }

    /// 默认无设置视图
    func makeSettingsView() -> AnyView? { nil }

    /// 默认空搜索结果
    func searchItems(query: String) async -> [SearchableItem] { [] }

    /// 默认无操作
    func activate() {}
    func deactivate() {}

    /// 默认不建表：只有用真表的插件才声明 schema
    static var storageMigrations: [SQLiteMigration] { [] }

    /// 默认一条「打开本插件」，关键词用触发词和名字
    static var commands: [CommandDescriptor] {
        [
            CommandDescriptor.openPlugin(
                id: id,
                name: name,
                icon: icon,
                keywords: triggerWords + [name],
                subtitle: description.isEmpty ? nil : description
            )
        ]
    }

    /// 默认不参与动态搜索，避免每次按键把所有插件都叫醒
    func accepts(query: String) -> Bool { false }

    /// 默认没有随查询变化的结果
    func dynamicSearch(query: String) async -> [SearchableItem] { [] }

    /// 默认把「打开本插件」导航进插件面板
    func perform(commandID: String) {
        guard commandID == CommandID.openPlugin(Self.id) else { return }
        EventBus.shared.post(NavigateEvent(pluginID: Self.id))
    }

    /// 默认取触发词裸查询的第一条
    ///
    /// 走插件自己的搜索路径而不是另造一份数据，所以首屏那条和搜索到的那条永远一致
    /// （标题、图标、动作都同一份代码产出）。启动器插件会覆盖它 —— 它提供的应用列表
    /// 是首屏的主体，不该再额外贡献一条。
    ///
    /// **相关度保持插件自己的取值**（通常 0.6~0.8，高于启动器应用条目的 0.5），
    /// 于是首屏顺序是「最近使用 → 插件命令 → 应用」：命令是启动器真正要做的事，
    /// 应用是一长串可以在搜索框里打名字的尾巴。这与 Fasty 的首屏一致
    /// （默认插件条目 + 最近使用），也避免了「首屏全是应用、一条命令都看不到」。
    func defaultItems() async -> [SearchableItem] {
        guard let trigger = Self.triggerWords.first else { return [] }
        return Array(await searchItems(query: trigger).prefix(1))
    }
}
