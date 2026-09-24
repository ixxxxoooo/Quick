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
        .init(
            id: "general.appearance", tab: .appearance, title: "Appearance & Theme / 外观与主题",
            subtitle: "General"),
        .init(
            id: "general.shortcuts", tab: .shortcuts, title: "Shortcuts & Hotkeys / 全局快捷键与命令唤醒",
            subtitle: "General"),
        .init(
            id: "general.paletteBehavior", tab: .general, title: "Panel Behaviour / 面板行为",
            subtitle: "General"),
        .init(
            id: "general.keyboardLayout", tab: .general, title: "Keyboard Layout / 强制键盘布局",
            subtitle: "General"),
        .init(id: "permissions", tab: .permissions, title: "Permissions / 系统权限", subtitle: "General"),
        .init(id: "search.sources", tab: .search, title: "Search Sources / 搜索来源", subtitle: "搜索"),
        .init(id: "launcher.scopes", tab: .search, title: "Search Scopes / 搜索范围", subtitle: "搜索"),
        .init(id: "plugins.launcher", tab: .applications, title: "应用启动器", subtitle: "插件"),
        .init(id: "plugins.system", tab: .systemActions, title: "系统控制", subtitle: "插件"),
        .init(id: "features.calculator", tab: .calculator, title: "Calculator / 计算器", subtitle: "插件"),
        .init(id: "features.filesearch", tab: .search, title: "File Search / 文件搜索", subtitle: "搜索来源"),
        .init(id: "features.snippets", tab: .snippets, title: "Snippets / 代码片段", subtitle: "插件"),
        .init(id: "features.notes", tab: .notes, title: "Notes / 便签备忘", subtitle: "插件"),
        .init(id: "features.calendar", tab: .calendar, title: "Calendar / 日历日程", subtitle: "插件"),
        .init(id: "features.ai", tab: .ai, title: "AI Assistant / AI 助手", subtitle: "插件"),
        .init(id: "features.translator", tab: .translator, title: "Translator / 划词翻译", subtitle: "插件"),
        .init(
            id: "features.jsonformatter", tab: .jsonFormatter, title: "JSON Formatter / JSON 格式化",
            subtitle: "插件"),
        .init(
            id: "features.sqlformatter", tab: .sqlFormatter, title: "SQL Formatter / SQL 格式化",
            subtitle: "插件"),
        .init(
            id: "features.base64codec", tab: .base64Codec, title: "Base64 Codec / Base64 编解码",
            subtitle: "插件"),
        .init(
            id: "features.urlcodec", tab: .urlCodec, title: "URL Codec / URL 编解码",
            subtitle: "插件"),
        .init(
            id: "features.uuidgenerator", tab: .uuidGenerator, title: "UUID Generator / UUID 生成器",
            subtitle: "插件"),
        .init(
            id: "features.hashcalculator", tab: .hashCalculator, title: "Hash Calculator / Hash 计算器",
            subtitle: "插件"),
        .init(
            id: "features.timestampconverter", tab: .timestampConverter,
            title: "Timestamp Converter / 时间戳转换", subtitle: "插件"),
        .init(
            id: "features.textdiff", tab: .textDiff, title: "Text Diff / 文本对比",
            subtitle: "插件"),
        .init(
            id: "features.markdownpreview", tab: .markdownPreview, title: "Markdown Preview / Markdown 预览",
            subtitle: "插件"),
        .init(
            id: "features.colorcompare", tab: .colorCompare, title: "Color Compare / 颜色工具",
            subtitle: "插件"),
        .init(
            id: "features.sysmonitor", tab: .systemMonitor, title: "System Monitor / 系统监控",
            subtitle: "插件"),
        .init(
            id: "features.killprocess", tab: .killProcess, title: "Kill Process / 结束进程",
            subtitle: "插件"),
        .init(
            id: "features.networktools", tab: .networkTools, title: "Network Tools / 网络诊断",
            subtitle: "插件"),
        .init(id: "features.ocr", tab: .ocr, title: "OCR / 文字识别", subtitle: "插件"),
        .init(id: "features.screenshot", tab: .screenshot, title: "Screenshot / 截图工具", subtitle: "插件"),
        .init(
            id: "features.superpanel", tab: .superPanel, title: "Super Panel / 超级面板",
            subtitle: "超级面板"),
        .init(
            id: "features.superpanel.mouse", tab: .superPanel,
            title: "Middle Click / Right Long Press / 中键 / 右键长按",
            subtitle: "超级面板鼠标唤出"),
        .init(
            id: "features.superpanel.appearance", tab: .superPanel,
            title: "Opacity & Material / 不透明度与背景材质",
            subtitle: "超级面板外观"),
        .init(
            id: "features.superpanel.tools", tab: .superPanel,
            title: "Quick Tools / 常用工具与最近使用",
            subtitle: "超级面板工作台"),
        .init(
            id: "ai.service", tab: .aiService, title: "AI Service / AI 服务",
            subtitle: "AI 基座"),
        .init(
            id: "ai.provider", tab: .aiService, title: "AI Provider / 服务商与 API Key",
            subtitle: "AI 服务"),
        .init(
            id: "ai.model", tab: .aiService, title: "AI Model / 模型与生成参数",
            subtitle: "AI 服务"),
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
