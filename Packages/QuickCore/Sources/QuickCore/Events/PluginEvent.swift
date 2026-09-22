// PluginEvent.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 插件事件协议
///
/// 所有插件间通信的事件都实现此协议。
/// 事件定义在 QuickCore 中，确保所有插件都能引用。
public protocol PluginEvent: Sendable {
    /// 事件唯一名称（用于 EventBus 内部路由）
    static var name: String { get }
}

// MARK: - 导航事件

/// 导航到指定插件
///
/// 典型场景：剪贴板识别到 JSON → 跳转到 DevTools 的 JSON 格式化。
/// context 用于传递额外数据，由目标插件自行解析。
public struct NavigateEvent: PluginEvent {
    public static let name = "quick.navigate"

    /// 目标插件 ID
    public let pluginID: String

    /// 附加上下文（键值对，插件自行解读）
    public let context: [String: String]

    public init(pluginID: String, context: [String: String] = [:]) {
        self.pluginID = pluginID
        self.context = context
    }
}

// MARK: - 剪贴板事件

/// 请求复制文本到剪贴板
///
/// 插件（如 OCR、计算器）产出结果后发布此事件，
/// 由 AppCore 路由到 PasteboardService 执行实际复制。
public struct CopyToClipboardEvent: PluginEvent {
    public static let name = "quick.clipboard.copy"

    /// 要复制的文本内容
    public let text: String

    /// 复制完成后是否显示 HUD 提示
    public let showHUD: Bool

    public init(text: String, showHUD: Bool = true) {
        self.text = text
        self.showHUD = showHUD
    }
}

// MARK: - HUD 消息事件

/// 显示轻量 HUD 消息
///
/// 插件可通过此事件向用户展示操作反馈（如"已复制"、"操作成功"）。
public struct ShowHUDEvent: PluginEvent {
    public static let name = "quick.hud.show"

    /// 消息内容
    public let message: String

    /// 消息语气
    public let tone: HUDTone

    public init(message: String, tone: HUDTone = .success) {
        self.message = message
        self.tone = tone
    }
}

/// HUD 消息语气
public enum HUDTone: Sendable {
    case success
    case info
    case warning
    case danger
}

// MARK: - 面板控制事件

/// 请求隐藏面板
public struct HidePaletteEvent: PluginEvent {
    public static let name = "quick.palette.hide"

    /// 是否恢复焦点到之前的应用
    public let restoreFocus: Bool

    public init(restoreFocus: Bool = true) {
        self.restoreFocus = restoreFocus
    }
}

/// 把当前剪贴板内容粘贴回「面板打开前的那个应用」
///
/// 剪贴板内容由调用方在此之前写好（`CopyToClipboardEvent` 或直接写 `NSPasteboard`）。
/// 宿主收到后：隐藏面板、把焦点交还之前的应用，等它回到前台再合成一次 ⌘V。
/// 需要辅助功能权限；没有权限时退化成「只完成复制」并提示用户。
public struct PasteIntoPreviousAppEvent: PluginEvent {
    public static let name = "quick.clipboard.pasteIntoPreviousApp"

    public init() {}
}

/// 请求显示面板并切换到指定插件
public struct ShowPaletteEvent: PluginEvent {
    public static let name = "quick.palette.show"

    /// 目标插件 ID（nil 则显示主搜索）
    public let pluginID: String?

    /// 预填搜索文本
    public let query: String?

    public init(pluginID: String? = nil, query: String? = nil) {
        self.pluginID = pluginID
        self.query = query
    }
}

/// 请求打开设置窗口
public struct ShowPaletteSettingsEvent: PluginEvent {
    public static let name = "quick.settings.show"

    public init() {}
}

/// 请求将当前插件面板分离为独立窗口
///
/// 插件模式下用户按 ⌘D 或点击分离按钮时发布。
/// AppCore 路由到 PluginPanelController 创建独立窗口。
public struct DetachPanelEvent: PluginEvent {
    public static let name = "quick.panel.detach"

    /// 要分离的插件 ID
    public let pluginID: String

    public init(pluginID: String) {
        self.pluginID = pluginID
    }
}

// MARK: - 应用索引事件

/// 应用索引刷新完成事件
public struct AppIndexRefreshedEvent: PluginEvent {
    public static let name = "quick.appindex.refreshed"

    public init() {}
}

/// 剪贴板内容发生了变化
///
/// 由剪贴板插件的监听器发出（它在轮询 `NSPasteboard.changeCount`，是唯一知道
/// 「刚刚复制过」的地方）。宿主订阅它做两件事：面板打开时判断要不要把内容填进搜索框。
///
/// 只带时间点，不带内容：内容谁需要谁去读剪贴板，避免把可能很大的文本在事件里传一遍。
/// 命令开关、别名或搜索来源变了
///
/// 设置页和插件设置写完偏好后发它，宿主据此重建命令快照并重新注册热键。
/// 不带具体改了哪条：快照本来就是整份替换，增量通知省不下多少，还容易漏。
public struct CommandCatalogChangedEvent: PluginEvent {
    public static let name = "quick.commandCatalog.changed"

    public init() {}
}

public struct ClipboardChangedEvent: PluginEvent {

    public static var name: String { "quick.clipboard.changed" }

    /// 变化发生的时刻
    public let at: Date

    public init(at: Date = Date()) {
        self.at = at
    }
}
