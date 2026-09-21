// SettingsKey.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 类型安全的设置键定义
///
/// 每个插件在 QuickCore 中注册自己的设置键，
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

    // MARK: - 启动器设置

    /// 应用搜索范围
    public static let launcherSearchScopes = "quick.launcher.searchScopes"

    /// 是否在启动器未命中时提供运行 Shell 命令回退
    public static let launcherRunShellFallback = "quick.launcher.runShellFallback"

    /// 自定义 Shell 命令列表数据
    public static let launcherCustomCommands = "quick.launcher.customCommands"

    /// 别名前缀
    public static func alias(for key: String) -> String {
        "quick.alias.\(key)"
    }

    // MARK: - 面板行为

    /// 面板打开时自动把剪贴板内容填进搜索框的时间窗（秒；0 = 关闭）
    ///
    /// 语义是「刚复制过东西就打开面板」——复制完立刻唤出面板，多半就是要拿它来搜索或粘贴。
    /// 超过这个时间窗的旧剪贴板内容不该自己冒出来。
    public static let paletteAutoPasteSeconds = "quick.palette.autoPasteSeconds"

    /// 搜索框内容自动清空的空闲时间（分钟；0 = 关闭）
    public static let paletteAutoClearMinutes = "quick.palette.autoClearMinutes"

    /// 面板打开期间强制切换到的键盘布局 id（空 = 不切换）
    public static let paletteForceKeyboardLayout = "quick.palette.forceKeyboardLayout"

    // MARK: - 插件开关前缀

    /// 生成插件启用状态的设置键
    /// - Parameter pluginID: 插件 ID
    /// - Returns: 设置键字符串
    public static func pluginEnabled(_ pluginID: String) -> String {
        "quick.plugin.\(pluginID).enabled"
    }
}
