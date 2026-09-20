// ModuleEvent.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 模块事件协议
///
/// 所有模块间通信的事件都实现此协议。
/// 事件定义在 QuickCore 中，确保所有模块都能引用。
public protocol ModuleEvent: Sendable {
    /// 事件唯一名称（用于 EventBus 内部路由）
    static var name: String { get }
}

// MARK: - 导航事件

/// 导航到指定模块
///
/// 典型场景：剪贴板识别到 JSON → 跳转到 DevTools 的 JSON 格式化。
/// context 用于传递额外数据，由目标模块自行解析。
public struct NavigateEvent: ModuleEvent {
    public static let name = "quick.navigate"

    /// 目标模块 ID
    public let moduleID: String

    /// 附加上下文（键值对，模块自行解读）
    public let context: [String: String]

    public init(moduleID: String, context: [String: String] = [:]) {
        self.moduleID = moduleID
        self.context = context
    }
}

// MARK: - 剪贴板事件

/// 请求复制文本到剪贴板
///
/// 模块（如 OCR、计算器）产出结果后发布此事件，
/// 由 AppCore 路由到 PasteboardService 执行实际复制。
public struct CopyToClipboardEvent: ModuleEvent {
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
/// 模块可通过此事件向用户展示操作反馈（如"已复制"、"操作成功"）。
public struct ShowHUDEvent: ModuleEvent {
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
public struct HidePaletteEvent: ModuleEvent {
    public static let name = "quick.palette.hide"

    /// 是否恢复焦点到之前的应用
    public let restoreFocus: Bool

    public init(restoreFocus: Bool = true) {
        self.restoreFocus = restoreFocus
    }
}

/// 请求显示面板并切换到指定模块
public struct ShowPaletteEvent: ModuleEvent {
    public static let name = "quick.palette.show"

    /// 目标模块 ID（nil 则显示主搜索）
    public let moduleID: String?

    /// 预填搜索文本
    public let query: String?

    public init(moduleID: String? = nil, query: String? = nil) {
        self.moduleID = moduleID
        self.query = query
    }
}
