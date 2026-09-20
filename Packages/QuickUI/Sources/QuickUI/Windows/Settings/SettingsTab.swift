// SettingsTab.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 设置窗口的分组结构（参考 Tinycast）
public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case launcher
    case features
    case advanced

    public var id: Self { self }

    public var title: String {
        switch self {
        case .general: "General"
        case .launcher: "Launcher"
        case .features: "Features"
        case .advanced: "Advanced"
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

    // MARK: - General
    case general
    case permissions

    // MARK: - Launcher
    case applications
    case systemActions
    case commands

    // MARK: - Features
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

    // MARK: - Advanced
    case about

    public var id: Self { self }

    /// 侧边栏标题
    public var title: String {
        switch self {
        case .general: "General"
        case .permissions: "Permissions"

        case .applications: "Applications"
        case .systemActions: "System Actions"
        case .commands: "Commands"

        case .clipboard: "Clipboard"
        case .calculator: "Calculator"
        case .fileSearch: "File Search"
        case .snippets: "Snippets"
        case .windowManagement: "Window Management"
        case .notes: "Notes"
        case .calendar: "Calendar"
        case .weather: "Weather"
        case .ai: "AI"
        case .translator: "Translator"
        case .devTools: "Developer Tools"
        case .systemMonitor: "System Monitor"
        case .networkTools: "Network Tools"
        case .ocr: "OCR"
        case .screenshot: "Screenshot"

        case .about: "About"
        }
    }

    /// 侧边栏图标（SF Symbol 名）
    public var systemImage: String {
        switch self {
        case .general: "switch.2"
        case .permissions: "lock.shield"

        case .applications: "square.grid.2x2"
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

    /// 对应功能模块 ID（若该分栏代表一个 Feature Module）
    public var moduleID: String? {
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
