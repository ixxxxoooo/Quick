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

    /// 面板缩放级别（1.0 / 1.1 / 1.2）
    public static let paletteScale = "quick.palette.scale"

    /// 用户拖过之后记住的面板高度。没拖过则用设计高度
    public static let paletteHeight = "quick.palette.height"

    /// 用户拖过之后记住的面板宽度。没拖过则用设计宽度
    public static let paletteWidth = "quick.palette.width"

    /// 面板弹出屏幕位置（cursor = 鼠标所在屏幕，main = 主显示器）
    public static let paletteScreen = "quick.palette.screen"

    /// 是否在搜索结果中显示行图标
    public static let showResultIcons = "quick.palette.showResultIcons"

    /// 是否在底栏显示快捷键提示胶囊
    public static let showBottomBarHints = "quick.palette.showBottomBarHints"

    /// 首次引导已经完成
    public static let onboardingCompleted = "quick.onboarding.completed"

    // MARK: - AI 基座

    /// 宿主级 AI 配置。其他插件通过 `AIService` 读这份配置访问 AI，不各自维护一份。
    public enum AI {
        /// 是否启用 AI 能力
        public static let enabled = "quick.ai.enabled"
        /// 服务商（`AIProviderKind.rawValue`）
        public static let provider = "quick.ai.provider"
        /// API Key
        public static let apiKey = "quick.ai.apiKey"
        /// 自定义 Base URL（空 = 用服务商默认）
        public static let baseURL = "quick.ai.baseURL"
        /// 模型名（空 = 用服务商默认）
        public static let model = "quick.ai.model"
        /// 单次最大生成 token 数
        public static let maxTokens = "quick.ai.maxTokens"
        /// 采样温度
        public static let temperature = "quick.ai.temperature"
    }

    // MARK: - 插件开关前缀

    /// 生成插件启用状态的设置键
    /// - Parameter pluginID: 插件 ID
    /// - Returns: 设置键字符串
    public static func pluginEnabled(_ pluginID: String) -> String {
        "quick.plugin.\(pluginID).enabled"
    }

    /// 单条命令是否打开。没写过视为打开，避免升级后命令从搜索和热键里消失
    public static func commandEnabled(_ commandID: String) -> String {
        "command.enabled.\(commandID)"
    }

    /// 某个插件是否参与主搜索。没写过视为参与
    public static func searchSourceEnabled(_ pluginID: String) -> String {
        "search.source.\(pluginID)"
    }
}
