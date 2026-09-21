// SettingsTab.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 设置窗口的分组结构
public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case launcher
    case features
    case advanced

    public var id: Self { self }

    public var title: String {
        switch self {
        case .general: "通用"
        case .launcher: "启动器"
        case .features: "功能插件"
        case .advanced: "高级"
        }
    }

    public var tabs: [SettingsTab] {
        switch self {
        case .general:
            return [.general, .appearance, .shortcuts, .permissions]
        case .launcher:
            return [.applications, .systemActions, .commands]
        case .features:
            return [
                .clipboard, .calculator, .fileSearch, .snippets,
                .notes, .calendar, .weather,
                .ai, .translator, .systemMonitor,
                .networkTools, .ocr, .screenshot,
                // 开发者工具：原先是一个 devtools 容器，现在每个工具都是独立插件
                .jsonFormatter, .sqlFormatter, .base64Codec, .urlCodec,
                .uuidGenerator, .hashCalculator, .timestampConverter,
                .wordCounter, .textDiff, .markdownPreview, .colorCompare,
                .superPanel
            ]
        case .advanced:
            return [.about]
        }
    }
}

/// 设置窗口的分栏
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {

    // MARK: - 通用
    case general
    case appearance
    case shortcuts
    case plugins
    case permissions

    // MARK: - 启动器
    case applications
    case systemActions
    case commands

    // MARK: - 功能插件
    case clipboard
    case calculator
    case fileSearch
    case snippets
    case notes
    case calendar
    case weather
    case ai
    case translator
    case jsonFormatter
    case sqlFormatter
    case base64Codec
    case urlCodec
    case uuidGenerator
    case hashCalculator
    case timestampConverter
    case wordCounter
    case textDiff
    case markdownPreview
    case colorCompare
    case systemMonitor
    case networkTools
    case ocr
    case screenshot
    case superPanel

    // MARK: - 高级
    case about

    public var id: Self { self }

    /// 侧边栏标题
    public var title: String {
        switch self {
        case .general: "通用设置"
        case .appearance: "外观"
        case .shortcuts: "快捷键"
        case .plugins: "插件管理"
        case .permissions: "权限"

        case .applications: "应用程序"
        case .systemActions: "系统操作"
        case .commands: "终端命令"

        case .clipboard: "剪贴板历史"
        case .calculator: "计算器"
        case .fileSearch: "文件搜索"
        case .snippets: "文本片段"
        case .notes: "笔记"
        case .calendar: "日历"
        case .weather: "天气"
        case .ai: "AI 聚合"
        case .translator: "翻译"
        case .jsonFormatter: "JSON 格式化"
        case .sqlFormatter: "SQL 格式化"
        case .base64Codec: "Base64 编解码"
        case .urlCodec: "URL 编解码"
        case .uuidGenerator: "UUID 生成器"
        case .hashCalculator: "Hash 计算器"
        case .timestampConverter: "时间戳转换"
        case .wordCounter: "字数统计"
        case .textDiff: "文本对比"
        case .markdownPreview: "Markdown 预览"
        case .colorCompare: "颜色工具"
        case .systemMonitor: "系统监控"
        case .networkTools: "网络工具"
        case .ocr: "文字识别"
        case .screenshot: "截图工具"
        case .superPanel: "超级面板"

        case .about: "关于"
        }
    }

    /// 侧边栏图标（SF Symbol 名）
    public var systemImage: String {
        switch self {
        case .general: "switch.2"
        case .appearance: "paintbrush"
        case .shortcuts: "command"
        case .plugins: "square.grid.2x2"
        case .permissions: "lock.shield"

        case .applications: "app.badge"
        case .systemActions: "bolt"
        case .commands: "terminal"

        case .clipboard: "doc.on.clipboard"
        case .calculator: "plus.forwardslash.minus"
        case .fileSearch: "doc.text.magnifyingglass"
        case .snippets: "curlybraces"
        case .notes: "text.page"
        case .calendar: "calendar"
        case .weather: "cloud.sun"
        case .ai: "sparkles"
        case .translator: "character.book.closed"
        case .jsonFormatter: "curlybraces"
        case .sqlFormatter: "cylinder"
        case .base64Codec: "lock.rectangle"
        case .urlCodec: "link"
        case .uuidGenerator: "number"
        case .hashCalculator: "number.square"
        case .timestampConverter: "clock"
        case .wordCounter: "textformat.123"
        case .textDiff: "doc.on.doc"
        case .markdownPreview: "text.badge.checkmark"
        case .colorCompare: "paintpalette"
        case .systemMonitor: "cpu"
        case .networkTools: "network"
        case .ocr: "text.viewfinder"
        case .screenshot: "camera"
        case .superPanel: "bolt.square"

        case .about: "info.circle"
        }
    }

    /// 对应功能插件 ID（若该分栏代表一个 Feature Plugin）
    public var pluginID: String? {
        switch self {
        case .applications: "launcher"
        case .systemActions: "systemcontrol"
        case .clipboard: "clipboard"
        case .calculator: "calculator"
        case .fileSearch: "filesearch"
        case .snippets: "snippets"
        case .notes: "notes"
        case .calendar: "calendar"
        case .weather: "weather"
        case .ai: "ai"
        case .translator: "translator"
        case .jsonFormatter: "json-formatter"
        case .sqlFormatter: "sql-formatter"
        case .base64Codec: "base64-codec"
        case .urlCodec: "url-codec"
        case .uuidGenerator: "uuid-generator"
        case .hashCalculator: "hash-calculator"
        case .timestampConverter: "timestamp-converter"
        case .wordCounter: "word-counter"
        case .textDiff: "text-diff"
        case .markdownPreview: "markdown-preview"
        case .colorCompare: "color-compare"
        case .systemMonitor: "sysmonitor"
        case .networkTools: "networktools"
        case .ocr: "ocr"
        case .screenshot: "screenshot"
        case .superPanel: "superPanel"
        default: nil
        }
    }
}
