// SettingsTab.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 设置窗口的分组
///
/// 上面是宿主自己的页面。`插件` 是侧边栏里的一级分类，每个插件是它下面的一项。
public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case host
    case plugins
    case about

    public var id: Self { self }

    public var title: String {
        switch self {
        case .host, .about: ""
        case .plugins: "插件"
        }
    }

    /// 宿主页面。插件列表不写死在这里，侧边栏按已注册插件生成
    public var tabs: [SettingsTab] {
        switch self {
        case .host: [.general, .appearance, .shortcuts, .permissions, .search]
        case .plugins: []
        case .about: [.about]
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
    case search

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
    case ai
    case translator
    case jsonFormatter
    case sqlFormatter
    case base64Codec
    case urlCodec
    case uuidGenerator
    case hashCalculator
    case timestampConverter
    case textDiff
    case markdownPreview
    case colorCompare
    case systemMonitor
    case killProcess
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
        case .general: "通用"
        case .appearance: "外观"
        case .shortcuts: "快捷键"
        case .plugins: "插件"
        case .permissions: "权限"
        case .search: "搜索"

        case .applications: "应用启动器"
        case .systemActions: "系统控制"
        case .commands: "终端命令"

        case .clipboard: "剪贴板历史"
        case .calculator: "计算器"
        case .fileSearch: "文件搜索"
        case .snippets: "文本片段"
        case .notes: "笔记"
        case .calendar: "日历"
        case .ai: "AI 聚合"
        case .translator: "翻译"
        case .jsonFormatter: "JSON 格式化"
        case .sqlFormatter: "SQL 格式化"
        case .base64Codec: "Base64 编解码"
        case .urlCodec: "URL 编解码"
        case .uuidGenerator: "UUID 生成器"
        case .hashCalculator: "Hash 计算器"
        case .timestampConverter: "时间戳转换"
        case .textDiff: "文本对比"
        case .markdownPreview: "Markdown 预览"
        case .colorCompare: "颜色工具"
        case .systemMonitor: "系统监控"
        case .killProcess: "结束进程"
        case .networkTools: "网络工具"
        case .ocr: "文字识别"
        case .screenshot: "截图工具"
        case .superPanel: "超级面板"

        case .about: "关于"
        }
    }

    /// 侧边栏图标（精选简洁 SF Symbol，落在小色块上仍清晰）
    public var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .shortcuts: "keyboard.fill"
        case .plugins: "puzzlepiece.extension.fill"
        case .permissions: "lock.fill"
        case .search: "magnifyingglass"

        case .applications: "square.grid.2x2.fill"
        case .systemActions: "power"
        case .commands: "terminal.fill"

        case .clipboard: "doc.on.clipboard.fill"
        case .calculator: "plus.forwardslash.minus"
        case .fileSearch: "folder.fill"
        case .snippets: "text.quote"
        case .notes: "note.text"
        case .calendar: "calendar"
        case .ai: "sparkles"
        case .translator: "globe"
        case .jsonFormatter: "curlybraces"
        case .sqlFormatter: "cylinder.fill"
        case .base64Codec: "lock.doc.fill"
        case .urlCodec: "link"
        case .uuidGenerator: "number"
        case .hashCalculator: "number.square.fill"
        case .timestampConverter: "clock.fill"
        case .textDiff: "arrow.left.arrow.right"
        case .markdownPreview: "text.alignleft"
        case .colorCompare: "paintpalette.fill"
        case .systemMonitor: "gauge.with.dots.needle.67percent"
        case .killProcess: "xmark.app.fill"
        case .networkTools: "wifi"
        case .ocr: "text.viewfinder"
        case .screenshot: "camera.fill"
        case .superPanel: "rectangle.3.group.fill"

        case .about: "info.circle.fill"
        }
    }

    /// 侧栏色块着色（与 `SettingsTileIcon.Tint` 一一对应，用字符串避免跨模块可见性问题）
    public var iconTintName: String {
        switch self {
        case .general: "gray"
        case .appearance: "pink"
        case .shortcuts: "orange"
        case .plugins: "indigo"
        case .permissions: "red"
        case .search: "blue"

        case .applications: "blue"
        case .systemActions: "orange"
        case .commands: "brown"

        case .clipboard: "mint"
        case .calculator: "orange"
        case .fileSearch: "yellow"
        case .snippets: "purple"
        case .notes: "yellow"
        case .calendar: "red"
        case .ai: "purple"
        case .translator: "teal"
        case .jsonFormatter: "green"
        case .sqlFormatter: "blue"
        case .base64Codec: "indigo"
        case .urlCodec: "cyan"
        case .uuidGenerator: "gray"
        case .hashCalculator: "brown"
        case .timestampConverter: "orange"
        case .textDiff: "pink"
        case .markdownPreview: "blue"
        case .colorCompare: "pink"
        case .systemMonitor: "green"
        case .killProcess: "red"
        case .networkTools: "cyan"
        case .ocr: "teal"
        case .screenshot: "purple"
        case .superPanel: "indigo"

        case .about: "gray"
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
        case .ai: "ai"
        case .translator: "translator"
        case .jsonFormatter: "json-formatter"
        case .sqlFormatter: "sql-formatter"
        case .base64Codec: "base64-codec"
        case .urlCodec: "url-codec"
        case .uuidGenerator: "uuid-generator"
        case .hashCalculator: "hash-calculator"
        case .timestampConverter: "timestamp-converter"
        case .textDiff: "text-diff"
        case .markdownPreview: "markdown-preview"
        case .colorCompare: "color-compare"
        case .systemMonitor: "sysmonitor"
        case .killProcess: "killprocess"
        case .networkTools: "networktools"
        case .ocr: "ocr"
        case .screenshot: "screenshot"
        case .superPanel: "superPanel"
        default: nil
        }
    }

    /// 按插件 id 找到它的设置页
    public static func tab(forPluginID pluginID: String) -> SettingsTab? {
        allCases.first { $0.pluginID == pluginID }
    }
}

extension SettingsTileIcon.Tint {
    /// 从 `SettingsTab.iconTintName` 还原色块色
    static func named(_ name: String) -> SettingsTileIcon.Tint {
        switch name {
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "gray": .gray
        case "brown": .brown
        default: .blue
        }
    }
}
