// SystemAction.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 系统操作枚举
///
/// 定义所有支持的系统控制操作。
public enum SystemAction: String, CaseIterable, Sendable {
    case lockScreen = "lock"
    case sleep = "sleep"
    case restart = "restart"
    case shutdown = "shutdown"
    case logout = "logout"
    case screenSaver = "screensaver"
    case emptyTrash = "emptytrash"
    case ejectAll = "ejectall"
    case toggleDarkMode = "darkmode"

    /// 显示标题
    public var title: String {
        switch self {
        case .lockScreen: "锁定屏幕"
        case .sleep: "睡眠"
        case .restart: "重新启动"
        case .shutdown: "关机"
        case .logout: "退出登录"
        case .screenSaver: "启动屏幕保护程序"
        case .emptyTrash: "清空废纸篓"
        case .ejectAll: "推出所有磁盘"
        case .toggleDarkMode: "切换深色模式"
        }
    }

    /// 操作描述
    public var description: String {
        switch self {
        case .lockScreen: "锁定当前会话"
        case .sleep: "将 Mac 置入睡眠状态"
        case .restart: "重新启动此 Mac"
        case .shutdown: "关闭此 Mac"
        case .logout: "退出当前用户登录"
        case .screenSaver: "立即启动屏幕保护程序"
        case .emptyTrash: "永久删除废纸篓中的所有项目"
        case .ejectAll: "安全推出所有可移除磁盘"
        case .toggleDarkMode: "在深色和浅色模式之间切换"
        }
    }

    /// SF Symbol 图标（参考 Tinycast SystemAction）
    public var icon: String {
        switch self {
        case .lockScreen: "lock"
        case .sleep: "moon.zzz"
        case .restart: "arrow.clockwise"
        case .shutdown: "power"
        case .logout: "rectangle.portrait.and.arrow.right"
        case .screenSaver: "rectangle.inset.filled"
        case .emptyTrash: "trash"
        case .ejectAll: "eject"
        case .toggleDarkMode: "circle.lefthalf.filled"
        }
    }

    /// 搜索关键词（中英文混合，参考 Fasty system-control 的 cmds）
    public var keywords: [String] {
        switch self {
        case .lockScreen: ["锁屏", "lock", "lock screen"]
        case .sleep: ["睡眠", "sleep", "休眠"]
        case .restart: ["重启", "restart", "reboot"]
        case .shutdown: ["关机", "shutdown", "shut down"]
        case .logout: ["注销", "logout", "log out"]
        case .screenSaver: ["屏保", "screensaver", "screen saver"]
        case .emptyTrash: ["废纸篓", "trash", "empty trash"]
        case .ejectAll: ["推出磁盘", "eject", "eject all"]
        case .toggleDarkMode: ["深色模式", "dark mode", "暗色"]
        }
    }

    /// 是否是不可撤销或会打断用户工作的操作，执行前应二次确认
    ///
    /// 重启、关机、退出登录会关掉所有未保存的工作；清空废纸篓是永久删除。
    /// 睡眠、锁屏、屏保、弹出磁盘、切换外观都能立刻恢复，不需要确认。
    public var requiresConfirmation: Bool {
        switch self {
        case .restart, .shutdown, .logout, .emptyTrash: true
        case .lockScreen, .sleep, .screenSaver, .ejectAll, .toggleDarkMode: false
        }
    }

    /// 确认按钮上的文字
    public var confirmTitle: String {
        switch self {
        case .restart: "重新启动"
        case .shutdown: "关机"
        case .logout: "退出登录"
        case .emptyTrash: "清空废纸篓"
        default: title
        }
    }

    /// 确认框的说明文字：说清后果
    public var confirmMessage: String {
        switch self {
        case .restart: "所有应用都会被关闭，未保存的内容可能丢失。"
        case .shutdown: "所有应用都会被关闭，未保存的内容可能丢失。"
        case .logout: "当前用户的所有应用都会被关闭，未保存的内容可能丢失。"
        case .emptyTrash: "废纸篓里的所有项目都会被永久删除，无法恢复。"
        default: description
        }
    }
}

/// 在列表里按输入筛选系统操作
///
/// 纯逻辑：标题、描述与关键词里任何一处包含输入（不分大小写）即命中；空输入返回全部。
public enum SystemActionFilter {

    public static func filter(_ actions: [SystemAction], query: String) -> [SystemAction] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return actions }
        return actions.filter { action in
            action.title.lowercased().contains(needle)
                || action.description.lowercased().contains(needle)
                || action.keywords.contains { $0.lowercased().contains(needle) }
        }
    }
}

/// 系统控制的偏好
public enum SystemControlPreferences {

    /// 破坏性操作执行前是否确认（未写过时为真）
    public static func confirmDestructive(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: PluginSettingKey.SystemControl.confirmDestructive) as? Bool ?? true
    }

    /// 这次执行要不要先问
    public static func shouldConfirm(_ action: SystemAction, defaults: UserDefaults = .standard) -> Bool {
        action.requiresConfirmation && confirmDestructive(defaults: defaults)
    }
}
