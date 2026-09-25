// PluginSettingKey.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 插件选项的键
///
/// ## 为什么要有这个文件
///
/// 插件选项存在 `UserDefaults` 里（那是放偏好的地方：用户可改、要能重置、量小），
/// 但键名原来只以字符串字面量的形式散落在各处：
///
/// ```swift
/// // 设置页
/// @AppStorage(PluginSettingKey.Clipboard.maxEntries) private var maxEntries = 500
/// // 存储层（同一个键，写错了不会有人发现）
/// UserDefaults.standard.integer(forKey: PluginSettingKey.Clipboard.maxEntries)
/// ```
///
/// 两处拼错一个字母就是「设置改了没反应」，而且编译器帮不上忙。键集中到这里之后，
/// 两边引用同一个常量，拼错会变成编译错误。
///
/// ## 约定
///
/// - 键名格式 `<插件名>.<选项>`，用驼峰插件名（`jsonFormatter`），不是插件 id
///   （`json-formatter`）。这条不一致是有历史原因的，**不要借机重命名** ——
///   键名是持久化契约，改了等于用户设置丢失。
/// - 每个键都必须在设置页里有一个对应的控件，否则用户无从修改它。
public enum PluginSettingKey {

    /// 剪贴板历史
    public enum Clipboard {
        /// 历史记录条数上限
        public static let maxEntries = "clipboard.maxEntries"
        /// 图片内容的总字节预算
        public static let imageByteBudget = "clipboard.imageByteBudget"
        /// 退出时清空历史
        public static let clearOnQuit = "clipboard.clearOnQuit"
        /// 是否监听剪贴板
        public static let monitorEnabled = "clipboard.monitorEnabled"
        /// 显示内容预览
        public static let showPreview = "clipboard.showPreview"
        /// 自动去重
        public static let deduplication = "clipboard.deduplication"
    }

    /// 计算器
    public enum Calculator {
        public static let precision = "calculator.precision"
        public static let useGroupingSeparator = "calculator.useGroupingSeparator"
        public static let autoCopy = "calculator.autoCopy"
    }

    /// 文本片段
    public enum Snippets {
        public static let autoExpand = "snippets.autoExpand"
        public static let showSnippetHint = "snippets.showSnippetHint"
    }

    /// 笔记
    public enum Notes {
        public static let autoSave = "notes.autoSave"
        public static let defaultFormat = "notes.defaultFormat"
    }

    /// 日历
    public enum Calendar {
        public static let reminderMinutes = "calendar.reminderMinutes"
        public static let autoExtractMeetingLinks = "calendar.autoExtractMeetingLinks"
        public static let showWeekNumber = "calendar.showWeekNumber"
    }

    /// AI 聚合插件的 UI 行为（置顶、Provider 开关）。键前缀 `ai.*`。
    ///
    /// 与 `SettingsKey.AI`（`quick.ai.*`）不同：后者是宿主 AI 基座，供 `AIService` 读 API/模型等。
    public enum AIPortal {
        public static let defaultAlwaysOnTop = "ai.defaultAlwaysOnTop"
        /// 单个 Provider 的开关
        public static func providerEnabled(_ providerID: String) -> String {
            "ai.provider.\(providerID).enabled"
        }
    }

    /// 翻译
    public enum Translator {
        public static let targetLang = "translator.targetLang"
    }

    /// 系统监控
    public enum SystemMonitor {
        public static let interval = "sysmonitor.interval"
        public static let showMenuBarStats = "sysmonitor.showMenuBarStats"
        public static let defaultTab = "sysmonitor.defaultTab"
        public static let displayModeCPU = "sysmonitor.displayModeCPU"
        public static let displayModeMemory = "sysmonitor.displayModeMemory"
        public static let displayModeDisk = "sysmonitor.displayModeDisk"
        public static let displayModeBattery = "sysmonitor.displayModeBattery"
    }

    /// 结束进程
    public enum KillProcess {
        public static let sortMode = "killprocess.sortMode"
        public static let refreshInterval = "killprocess.refreshInterval"
        public static let showPID = "killprocess.showPID"
        public static let searchInPath = "killprocess.searchInPath"
        public static let searchInPID = "killprocess.searchInPID"
    }

    /// 网络工具
    public enum NetworkTools {
        public static let pingCount = "networkTools.pingCount"
        public static let timeout = "networkTools.timeout"
        public static let showExternalIP = "networkTools.showExternalIP"
    }

    /// 文字识别
    public enum OCR {
        public static let autoCopy = "ocr.autoCopy"
        public static let language = "ocr.language"
    }

    /// 截图
    public enum Screenshot {
        public static let format = "screenshot.format"
        public static let saveToDesktop = "screenshot.saveToDesktop"
    }

    /// JSON 格式化
    public enum JSONFormatter {
        public static let indent = "jsonFormatter.indent"
    }

    /// UUID 生成器
    public enum UUIDGenerator {
        public static let uppercase = "uuidGenerator.uppercase"
        public static let removeDashes = "uuidGenerator.removeDashes"
    }

    /// SQL 格式化
    public enum SQLFormatter {
        public static let keywordCase = "sqlFormatter.keywordCase"
        public static let indent = "sqlFormatter.indent"
    }

    /// Base64 编解码
    public enum Base64Codec {
        public static let urlSafe = "base64Codec.urlSafe"
        public static let wrapLines = "base64Codec.wrapLines"
    }

    /// URL 编解码
    public enum URLCodec {
        public static let encodeSpacesAsPluses = "urlCodec.encodeSpacesAsPluses"
        public static let encodeFullUrl = "urlCodec.encodeFullUrl"
    }

    /// Hash 计算器
    public enum HashCalculator {
        public static let uppercase = "hashCalculator.uppercase"
        public static let autoCopy = "hashCalculator.autoCopy"
    }

    /// 时间戳转换
    public enum TimestampConverter {
        public static let defaultUnit = "timestampConverter.defaultUnit"
        public static let timeZone = "timestampConverter.timeZone"
    }

    /// 文本对比
    public enum TextDiff {
        public static let ignoreWhitespace = "textDiff.ignoreWhitespace"
        public static let ignoreCase = "textDiff.ignoreCase"
    }

    /// Markdown 预览
    public enum MarkdownPreview {
        public static let showLineNumbers = "markdownPreview.showLineNumbers"
        public static let enableMathJax = "markdownPreview.enableMathJax"
    }

    /// 颜色工具
    public enum ColorCompare {
        public static let defaultFormat = "colorCompare.defaultFormat"
        public static let uppercaseHex = "colorCompare.uppercaseHex"
    }

    /// 终端
    public enum Shell {
        public static let preferredTerminal = "shell.preferredTerminal"
    }

    // 超级面板的偏好键不在插件命名空间里：它已升级为宿主组件，
    // 键定义随实现移到 `QuickUI/SuperPanel/Model/SuperPanelPreferences.swift`。
}
