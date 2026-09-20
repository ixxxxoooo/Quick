// SettingsSearchCatalog.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 侧边栏搜索的一条结果
struct SettingsSearchEntry: Identifiable, Hashable {
    let id: String
    let tab: SettingsTab
    let title: String
    let subtitle: String?
}

/// 设置项索引
enum SettingsSearchCatalog {

    /// 静态条目
    private static let staticEntries: [SettingsSearchEntry] = [
        .init(
            id: "general.launchAtLogin", tab: .general, title: "Launch at Login / 开机启动", subtitle: "General"),
        .init(id: "general.hotkey", tab: .general, title: "Global Hotkey / 全局快捷键", subtitle: "General"),
        .init(id: "permissions", tab: .permissions, title: "Permissions / 系统权限", subtitle: "General"),
        .init(
            id: "launcher.applications", tab: .applications, title: "Applications / 应用程序",
            subtitle: "Launcher"),
        .init(id: "launcher.scopes", tab: .applications, title: "Search Scopes / 搜索范围", subtitle: "Launcher"),
        .init(
            id: "launcher.systemActions", tab: .systemActions, title: "System Actions / 系统操作",
            subtitle: "Launcher"),
        .init(id: "launcher.commands", tab: .commands, title: "Commands / 终端与命令", subtitle: "Launcher"),
        .init(id: "features.clipboard", tab: .clipboard, title: "Clipboard / 剪贴板历史", subtitle: "Features"),
        .init(id: "features.calculator", tab: .calculator, title: "Calculator / 计算器", subtitle: "Features"),
        .init(id: "features.filesearch", tab: .fileSearch, title: "File Search / 文件搜索", subtitle: "Features"),
        .init(id: "features.snippets", tab: .snippets, title: "Snippets / 代码片段", subtitle: "Features"),
        .init(
            id: "features.windowmanager", tab: .windowManagement, title: "Window Management / 窗口管理",
            subtitle: "Features"),
        .init(id: "features.notes", tab: .notes, title: "Notes / 便签备忘", subtitle: "Features"),
        .init(id: "features.calendar", tab: .calendar, title: "Calendar / 日历日程", subtitle: "Features"),
        .init(id: "features.weather", tab: .weather, title: "Weather / 实时天气", subtitle: "Features"),
        .init(id: "features.ai", tab: .ai, title: "AI Assistant / AI 助手", subtitle: "Features"),
        .init(id: "features.translator", tab: .translator, title: "Translator / 划词翻译", subtitle: "Features"),
        .init(
            id: "features.jsonformatter", tab: .jsonFormatter, title: "JSON Formatter / JSON 格式化",
            subtitle: "Developer Tools"),
        .init(
            id: "features.sqlformatter", tab: .sqlFormatter, title: "SQL Formatter / SQL 格式化",
            subtitle: "Developer Tools"),
        .init(
            id: "features.base64codec", tab: .base64Codec, title: "Base64 Codec / Base64 编解码",
            subtitle: "Developer Tools"),
        .init(
            id: "features.urlcodec", tab: .urlCodec, title: "URL Codec / URL 编解码",
            subtitle: "Developer Tools"),
        .init(
            id: "features.uuidgenerator", tab: .uuidGenerator, title: "UUID Generator / UUID 生成器",
            subtitle: "Developer Tools"),
        .init(
            id: "features.hashcalculator", tab: .hashCalculator, title: "Hash Calculator / Hash 计算器",
            subtitle: "Developer Tools"),
        .init(
            id: "features.timestampconverter", tab: .timestampConverter,
            title: "Timestamp Converter / 时间戳转换", subtitle: "Developer Tools"),
        .init(
            id: "features.wordcounter", tab: .wordCounter, title: "Word Counter / 字数统计",
            subtitle: "Developer Tools"),
        .init(
            id: "features.textdiff", tab: .textDiff, title: "Text Diff / 文本对比",
            subtitle: "Developer Tools"),
        .init(
            id: "features.markdownpreview", tab: .markdownPreview, title: "Markdown Preview / Markdown 预览",
            subtitle: "Developer Tools"),
        .init(
            id: "features.colorcompare", tab: .colorCompare, title: "Color Compare / 颜色工具",
            subtitle: "Developer Tools"),
        .init(
            id: "features.sysmonitor", tab: .systemMonitor, title: "System Monitor / 系统监控",
            subtitle: "Features"),
        .init(
            id: "features.networktools", tab: .networkTools, title: "Network Tools / 网络诊断",
            subtitle: "Features"),
        .init(id: "features.ocr", tab: .ocr, title: "OCR / 文字识别", subtitle: "Features"),
        .init(id: "features.screenshot", tab: .screenshot, title: "Screenshot / 截图工具", subtitle: "Features"),
        .init(id: "about.version", tab: .about, title: "About / 关于 Quick", subtitle: "Advanced")
    ]

    /// 按关键词搜索
    static func results(for query: String, plugins: [SettingsPlugin]) -> [SettingsSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        return staticEntries.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.subtitle?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }
}
