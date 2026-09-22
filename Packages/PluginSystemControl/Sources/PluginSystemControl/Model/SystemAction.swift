// SystemAction.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

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
    case toggleDoNotDisturb = "dnd"

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
        case .toggleDoNotDisturb: "切换勿扰模式"
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
        case .toggleDoNotDisturb: "切换系统勿扰模式"
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
        case .toggleDoNotDisturb: "bell.slash"
        }
    }

    /// 搜索关键词（中英文混合，参考 Fasty system-control 的 cmds）
    public var keywords: [String] {
        switch self {
        case .lockScreen: ["锁屏", "锁定", "lock", "lock screen"]
        case .sleep: ["睡眠", "休眠", "sleep"]
        case .restart: ["重启", "重新启动", "restart", "reboot"]
        case .shutdown: ["关机", "关闭", "shutdown", "shut down"]
        case .logout: ["注销", "登出", "退出登录", "logout", "log out"]
        case .screenSaver: ["屏保", "屏幕保护", "screensaver", "screen saver"]
        case .emptyTrash: ["清空废纸篓", "废纸篓", "trash", "empty trash"]
        case .ejectAll: ["全部弹出", "弹出全部", "推出磁盘", "eject", "eject all"]
        case .toggleDarkMode: ["深色模式", "暗色", "浅色", "dark mode", "light", "theme", "主题", "切换"]
        case .toggleDoNotDisturb: ["勿扰", "免打扰", "do not disturb", "dnd"]
        }
    }
}
