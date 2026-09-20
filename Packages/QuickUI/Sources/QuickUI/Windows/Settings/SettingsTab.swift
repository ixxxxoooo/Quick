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
            return [.general, .permissions]
        case .launcher:
            return [.applications, .systemActions, .commands]
        case .features:
            return [
                .clipboard, .calculator, .fileSearch, .snippets,
                .windowManagement, .notes, .calendar, .weather,
                .ai, .translator, .devTools, .systemMonitor,
                .networkTools, .ocr, .screenshot
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
    case windowManagement
    case notes
    case calendar
    case weather
    case ai
    case translator
    case devTools
    case systemMonitor
    case networkTools
    case ocr
    case screenshot

    // MARK: - 高级
    case about

    public var id: Self { self }

    /// 侧边栏标题
    public var title: String {
        switch self {
        case .general: "通用设置"
        case .plugins: "插件管理"
        case .permissions: "权限"

        case .applications: "应用程序"
        case .systemActions: "系统操作"
        case .commands: "终端命令"

        case .clipboard: "剪贴板历史"
        case .calculator: "计算器"
        case .fileSearch: "文件搜索"
        case .snippets: "文本片段"
        case .windowManagement: "窗口管理"
        case .notes: "笔记"
        case .calendar: "日历"
        case .weather: "天气"
        case .ai: "AI 聚合"
        case .translator: "翻译"
        case .devTools: "开发工具"
        case .systemMonitor: "系统监控"
        case .networkTools: "网络工具"
        case .ocr: "文字识别"
        case .screenshot: "截图工具"

        case .about: "关于"
        }
    }

    /// 侧边栏图标（SF Symbol 名）
    public var systemImage: String {
        switch self {
        case .general: "switch.2"
        case .plugins: "square.grid.2x2"
        case .permissions: "lock.shield"

        case .applications: "app.badge"
        case .systemActions: "bolt"
        case .commands: "terminal"

        case .clipboard: "doc.on.clipboard"
        case .calculator: "plus.forwardslash.minus"
        case .fileSearch: "doc.text.magnifyingglass"
        case .snippets: "curlybraces"
        case .windowManagement: "macwindow"
        case .notes: "text.page"
        case .calendar: "calendar"
        case .weather: "cloud.sun"
        case .ai: "sparkles"
        case .translator: "character.book.closed"
        case .devTools: "wrench.and.screwdriver"
        case .systemMonitor: "cpu"
        case .networkTools: "network"
        case .ocr: "text.viewfinder"
        case .screenshot: "camera"

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
        case .windowManagement: "windowmanager"
        case .notes: "notes"
        case .calendar: "calendar"
        case .weather: "weather"
        case .ai: "ai"
        case .translator: "translator"
        case .devTools: "devtools"
        case .systemMonitor: "sysmonitor"
        case .networkTools: "networktools"
        case .ocr: "ocr"
        case .screenshot: "screenshot"
        default: nil
        }
    }
}
