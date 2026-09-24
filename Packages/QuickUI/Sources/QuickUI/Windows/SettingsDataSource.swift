// SettingsDataSource.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import SwiftUI

/// 一个可选的键盘布局
public struct SettingsKeyboardLayout: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// 设置窗口里的一行插件
public struct SettingsPlugin: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let icon: String
    public let description: String
    public let triggerWords: [String]

    public init(
        id: String,
        name: String,
        icon: String,
        description: String = "",
        triggerWords: [String] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.triggerWords = triggerWords
    }
}

/// 应用程序设置项
public struct SettingsAppItem: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let bundleID: String
    public let path: String
    public let isSystemApp: Bool
    public let alias: String?

    public init(
        id: String,
        name: String,
        bundleID: String,
        path: String,
        isSystemApp: Bool,
        alias: String? = nil
    ) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.isSystemApp = isSystemApp
        self.alias = alias
    }
}

/// 系统操作设置项
public struct SettingsSystemActionItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let icon: String
    public let alias: String?
    public let isEnabled: Bool

    public init(
        id: String,
        title: String,
        description: String,
        icon: String,
        alias: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.icon = icon
        self.alias = alias
        self.isEnabled = isEnabled
    }
}

/// 自定义命令设置项
public struct SettingsCustomCommandItem: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let command: String
    public let isEnabled: Bool
    public let alias: String?
    public let workingDirectory: String?
    /// 是否用交互式 shell 执行（`.zshrc` 里的别名与 PATH 才在）
    public let loadsShellEnvironment: Bool

    public init(
        id: UUID,
        name: String,
        command: String,
        isEnabled: Bool,
        alias: String? = nil,
        workingDirectory: String? = nil,
        loadsShellEnvironment: Bool = false
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.isEnabled = isEnabled
        self.alias = alias
        self.workingDirectory = workingDirectory
        self.loadsShellEnvironment = loadsShellEnvironment
    }
}

/// 设置页里的一项系统权限
public enum SettingsPermission: String, CaseIterable, Sendable {
    case accessibility
    case screenCapture
    case location

    public var title: String {
        switch self {
        case .accessibility: "辅助功能"
        case .screenCapture: "屏幕录制"
        case .location: "定位服务"
        }
    }

    public var systemImage: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenCapture: "rectangle.dashed.badge.record"
        case .location: "location"
        }
    }

    public var purpose: String {
        switch self {
        case .accessibility:
            "用于需要辅助功能的插件操作。系统只允许已授权的应用控制其他界面。"
        case .screenCapture:
            "用于截图与窗口捕获。macOS 只允许已授权的应用读取屏幕内容。"
        case .location:
            "用于天气插件。只在你主动查看天气时申请，不会在启动时弹出。"
        }
    }
}

/// 一项权限的当前状态
public struct SettingsPermissionState: Sendable {
    public let isGranted: Bool
    public let canRequest: Bool

    public init(isGranted: Bool, canRequest: Bool) {
        self.isGranted = isGranted
        self.canRequest = canRequest
    }
}

/// 快捷键页里的一行：左边是已录制的键，右边是命令
public struct SettingsCommandBinding: Identifiable, Sendable {
    public let id: String
    public let title: String
    /// 命令的补充说明（功能一句话），没有则不显示
    public let subtitle: String?
    public let pluginName: String
    public let icon: String
    public let isInvocationEnabled: Bool
    public let keycaps: [String]?
    /// 唤醒这条功能的关键字。用户在主面板或快捷键页输入其中任意一个
    public let keywords: [String]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        pluginName: String,
        icon: String,
        isInvocationEnabled: Bool,
        keycaps: [String]?,
        keywords: [String] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.pluginName = pluginName
        self.icon = icon
        self.isInvocationEnabled = isInvocationEnabled
        self.keycaps = keycaps
        self.keywords = keywords
    }

    /// 快捷键页里展示的那个关键字：优先用声明的唤醒词，没有就用标题
    public var wakeKeyword: String {
        keywords.first ?? title
    }
}

/// 主搜索的一个来源
public struct SettingsSearchSource: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public let isEnabled: Bool

    public init(id: String, title: String, subtitle: String, icon: String, isEnabled: Bool) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isEnabled = isEnabled
    }
}

/// AI 连接自检结果
public struct SettingsAITestResult: Sendable {
    public let isSuccess: Bool
    public let message: String

    public init(isSuccess: Bool, message: String) {
        self.isSuccess = isSuccess
        self.message = message
    }
}

/// 设置窗口的数据源与动作
///
/// **按职责拆成四个子协议再组合**：这个协议有约 50 个成员，而实际用得最多的视图
/// 也只用 7 个（见 docs/refactor-plan.md Phase 4 的统计）。视图只声明它真正需要的
/// 那一片，改动时的影响面才可推理。
///
/// `SettingsBridge` 一个类型实现全部四个 —— 组合优于继承，实现的还是一份。
@MainActor
public protocol SettingsDataSource:
    CommandSettingsDataSource,
    LauncherSettingsDataSource,
    PluginSettingsDataSource,
    HostSettingsDataSource
{
}

/// 快捷键与命令
@MainActor
public protocol CommandSettingsDataSource: AnyObject {

    /// 唤出主面板当前的键帽。清空后是 ⌥Space
    var togglePaletteKeycaps: [String] { get }
    /// 把录到的 Carbon 键码格式化成键帽，给还没落盘的草稿用
    func shortcutKeycaps(keyCode: Int, carbonModifiers: Int) -> [String]
    /// 已经绑了快捷键的命令，不含唤出主面板
    func boundCommandBindings() -> [SettingsCommandBinding]
    /// 把用户输入的关键字解析成唯一一条命令。对不上、或同时对上多条时返回 nil
    func resolveKeyword(_ keyword: String) -> SettingsCommandBinding?
    /// 把已有快捷键改绑到另一个关键字。成功返回 nil，失败返回给用户看的原因
    func retargetShortcut(from commandID: String, keyword: String) -> String?
    /// 某个插件声明的命令，给插件页介绍用
    func pluginCommands(_ pluginID: String) -> [SettingsCommandBinding]
    /// 录制成功返回 true；组合键已被占用时返回 false，偏好不变
    func setCommandShortcut(keyCode: Int, carbonModifiers: Int, for commandID: String) -> Bool
    func clearCommandShortcut(for commandID: String)
    func isCommandEnabled(_ commandID: String) -> Bool
    func setCommandEnabled(_ commandID: String, enabled: Bool)
}

/// 启动器：搜索范围、系统操作、自定义命令
@MainActor
public protocol LauncherSettingsDataSource: AnyObject {

    var searchScopes: [String] { get }
    func setSearchScopes(_ scopes: [String])
    func restoreDefaultSearchScopes()
    var indexedApplications: [SettingsAppItem] { get }
    func appIcon(for path: String) -> NSImage?
    func setAppAlias(_ alias: String?, for bundleID: String)

    var systemActions: [SettingsSystemActionItem] { get }
    func setSystemActionAlias(_ alias: String?, for id: String)

    var isRunShellFallbackEnabled: Bool { get }
    func setRunShellFallbackEnabled(_ enabled: Bool)
    var customCommands: [SettingsCustomCommandItem] { get }
    func addCustomCommand(
        name: String, command: String, workingDirectory: String?, loadsShellEnvironment: Bool)
    func updateCustomCommand(
        id: UUID, name: String, command: String, isEnabled: Bool, alias: String?,
        workingDirectory: String?, loadsShellEnvironment: Bool)
    func deleteCustomCommand(id: UUID)
}

/// 插件：开关、搜索来源、专属设置页
@MainActor
public protocol PluginSettingsDataSource: AnyObject {

    var searchSources: [SettingsSearchSource] { get }
    func setSearchSourceEnabled(_ pluginID: String, enabled: Bool)

    var pluginEntries: [SettingsPlugin] { get }
    func isPluginEnabled(_ id: String) -> Bool
    func setPluginEnabled(_ id: String, enabled: Bool)
    func makeFeatureSettingsView(for tab: SettingsTab) -> AnyView?

    /// 系统里可选的键盘布局
    ///
    /// 与窗口布局命令同理：设置页不认识 QuickPlatform，由组装层把系统能力映射过来。
    var keyboardLayouts: [SettingsKeyboardLayout] { get }

    /// 面板打开时强制切换到的布局 id（nil / 空 = 不切换）
    var forcedKeyboardLayoutID: String? { get }
    func setForcedKeyboardLayout(_ layoutID: String?)
}

/// 宿主级：通用、超级面板、AI、权限、关于
@MainActor
public protocol HostSettingsDataSource: AnyObject {

    // MARK: - 通用
    var isLaunchAtLoginEnabled: Bool { get }
    func setLaunchAtLogin(_ enabled: Bool)
    var hotKeyDescription: String { get }

    // MARK: - 超级面板（宿主级）
    /// 超级面板的设置页
    ///
    /// 超级面板不是插件，它的设置页由组装层直接提供，不走 `pluginEntries`。
    func makeSuperPanelSettingsView() -> AnyView
    /// 唤出超级面板的全局快捷键键帽
    var superPanelShortcutKeycaps: [String]? { get }
    /// 录制超级面板快捷键；冲突返回 false
    func setSuperPanelShortcut(keyCode: Int, carbonModifiers: Int) -> Bool
    func clearSuperPanelShortcut()
    /// 清空「最近使用」记录
    func clearRecentUsage()

    // MARK: - AI 基座
    /// 宿主级 AI 服务设置页
    func makeAISettingsView() -> AnyView
    /// 连接自检（发一条最短消息）
    func testAIConnection() async -> SettingsAITestResult

    // MARK: - 权限
    func permissionState(_ permission: SettingsPermission) -> SettingsPermissionState
    func requestPermission(_ permission: SettingsPermission)
    func openPermissionSettings(_ permission: SettingsPermission)

    // MARK: - 关于
    var versionDescription: String { get }
    var bundleIdentifier: String { get }
    var panelGeometryDescription: String { get }
}
