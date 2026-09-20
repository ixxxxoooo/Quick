// HotKeyAction.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 全局快捷键可绑定的操作
public enum HotKeyAction: Hashable, Sendable {

    /// 呼出/隐藏主面板（默认 ⌥Space）
    case togglePalette

    /// 启动/激活指定 Bundle ID 的应用
    case app(bundleID: String)

    /// 执行指定的系统控制操作（如 lockScreen, sleep, restart 等）
    case systemAction(id: String)

    /// 运行自定义 Shell 命令
    case customCommand(id: UUID)

    /// 持久化与 Carbon 注册用的唯一标识
    public var defaultsKey: String {
        switch self {
        case .togglePalette:
            return "hotkey.togglePalette"
        case .app(let bundleID):
            return "hotkey.app." + bundleID
        case .systemAction(let id):
            return "hotkey.systemAction." + id
        case .customCommand(let id):
            return "hotkey.customCommand." + id.uuidString.lowercased()
        }
    }
}
