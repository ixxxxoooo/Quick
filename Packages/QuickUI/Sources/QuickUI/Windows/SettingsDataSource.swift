// SettingsDataSource.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import SwiftUI

/// 设置窗口里的一行模块
public struct SettingsModule: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let icon: String
    public let triggerWords: [String]

    public init(id: String, name: String, icon: String, triggerWords: [String] = []) {
        self.id = id
        self.name = name
        self.icon = icon
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
    public let shortcutKeycaps: [String]?

    public init(
        id: String,
        name: String,
        bundleID: String,
        path: String,
        isSystemApp: Bool,
        alias: String? = nil,
        shortcutKeycaps: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.isSystemApp = isSystemApp
        self.alias = alias
        self.shortcutKeycaps = shortcutKeycaps
    }
}

/// 系统操作设置项
public struct SettingsSystemActionItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let icon: String
    public let alias: String?
    public let shortcutKeycaps: [String]?

    public init(
        id: String,
        title: String,
        description: String,
        icon: String,
        alias: String? = nil,
        shortcutKeycaps: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.icon = icon
        self.alias = alias
        self.shortcutKeycaps = shortcutKeycaps
    }
}

/// 自定义命令设置项
public struct SettingsCustomCommandItem: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let command: String
    public let isEnabled: Bool
    public let alias: String?
    public let shortcutKeycaps: [String]?
    public let workingDirectory: String?

    public init(
        id: UUID,
        name: String,
        command: String,
        isEnabled: Bool,
        alias: String? = nil,
        shortcutKeycaps: [String]? = nil,
        workingDirectory: String? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.isEnabled = isEnabled
        self.alias = alias
        self.shortcutKeycaps = shortcutKeycaps
        self.workingDirectory = workingDirectory
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
            "用于窗口管理（移动/缩放其他应用的窗口）。系统只允许已授权的应用这样做。"
        case .screenCapture:
            "用于截图与窗口捕获。macOS 只允许已授权的应用读取屏幕内容。"
        case .location:
            "用于天气模块。只在你主动查看天气时申请，不会在启动时弹出。"
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

/// 设置窗口的数据源与动作
@MainActor
public protocol SettingsDataSource: AnyObject {

    // MARK: - 通用
    var isLaunchAtLoginEnabled: Bool { get }
    func setLaunchAtLogin(_ enabled: Bool)
    var hotKeyDescription: String { get }
    var globalShortcutKeycaps: [String]? { get }
    func setGlobalShortcut(keyCode: Int, carbonModifiers: Int)
    func clearGlobalShortcut()

    // MARK: - 启动器：应用与搜索范围
    var searchScopes: [String] { get }
    func setSearchScopes(_ scopes: [String])
    func restoreDefaultSearchScopes()
    var indexedApplications: [SettingsAppItem] { get }
    func appIcon(for path: String) -> NSImage?
    func setAppAlias(_ alias: String?, for bundleID: String)
    func setAppShortcut(keyCode: Int, carbonModifiers: Int, for bundleID: String)
    func clearAppShortcut(for bundleID: String)

    // MARK: - 启动器：系统操作
    var systemActions: [SettingsSystemActionItem] { get }
    func setSystemActionAlias(_ alias: String?, for id: String)
    func setSystemActionShortcut(keyCode: Int, carbonModifiers: Int, for id: String)
    func clearSystemActionShortcut(for id: String)

    // MARK: - 启动器：Shell 与自定义命令
    var isRunShellFallbackEnabled: Bool { get }
    func setRunShellFallbackEnabled(_ enabled: Bool)
    var customCommands: [SettingsCustomCommandItem] { get }
    func addCustomCommand(name: String, command: String, workingDirectory: String?)
    func updateCustomCommand(
        id: UUID, name: String, command: String, isEnabled: Bool, alias: String?, workingDirectory: String?)
    func deleteCustomCommand(id: UUID)
    func setCustomCommandShortcut(keyCode: Int, carbonModifiers: Int, for id: UUID)
    func clearCustomCommandShortcut(for id: UUID)

    // MARK: - 功能模块设置
    var moduleEntries: [SettingsModule] { get }
    func isModuleEnabled(_ id: String) -> Bool
    func setModuleEnabled(_ id: String, enabled: Bool)
    func makeFeatureSettingsView(for tab: SettingsTab) -> AnyView?
    func moduleShortcutKeycaps(for moduleID: String) -> [String]?
    func setModuleShortcut(keyCode: Int, carbonModifiers: Int, for moduleID: String)
    func clearModuleShortcut(for moduleID: String)

    // MARK: - 权限
    func permissionState(_ permission: SettingsPermission) -> SettingsPermissionState
    func requestPermission(_ permission: SettingsPermission)
    func openPermissionSettings(_ permission: SettingsPermission)

    // MARK: - 关于
    var versionDescription: String { get }
    var bundleIdentifier: String { get }
    var panelGeometryDescription: String { get }
}
