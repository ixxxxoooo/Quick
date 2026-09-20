// SettingsKey.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 类型安全的设置键定义
///
/// 每个模块在 QuickCore 中注册自己的设置键，
/// 避免字符串硬编码和键冲突。
public enum SettingsKey {

    // MARK: - 通用设置

    /// 全局快捷键（默认 ⌥Space）
    public static let globalHotKey = "quick.global.hotkey"

    /// 是否开机自启
    public static let launchAtLogin = "quick.global.launchAtLogin"

    /// 外观模式（跟随系统 / 深色 / 浅色）
    public static let appearance = "quick.global.appearance"

    /// 是否显示菜单栏图标
    public static let showInMenuBar = "quick.global.showInMenuBar"

    /// 面板透明度（-100 ~ 100）
    public static let panelTransparency = "quick.global.panelTransparency"

    // MARK: - 模块开关前缀

    /// 生成模块启用状态的设置键
    /// - Parameter moduleID: 模块 ID
    /// - Returns: 设置键字符串
    public static func moduleEnabled(_ moduleID: String) -> String {
        "quick.module.\(moduleID).enabled"
    }
}
