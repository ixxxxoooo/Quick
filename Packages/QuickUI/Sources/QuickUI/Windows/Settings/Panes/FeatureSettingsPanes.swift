// FeatureSettingsPanes.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 功能插件独立设置页容器
///
/// 每个功能插件的设置页结构：
/// 1. 启用开关 + 在启动器中显示
/// 2. 触发词列表（展示中英双语唤醒命令）
/// 3. 全局快捷键绑定（快速打开插件面板）
/// 4. 插件专属配置项
struct FeatureSettingsPane: View {

    let tab: SettingsTab
    let dataSource: any SettingsDataSource

    @State private var isEnabled: Bool
    @State private var showInLauncher = true

    init(tab: SettingsTab, dataSource: any SettingsDataSource) {
        self.tab = tab
        self.dataSource = dataSource
        let modID = tab.moduleID ?? ""
        _isEnabled = State(initialValue: dataSource.isModuleEnabled(modID))
    }

    /// 查找当前模块的元信息
    private var moduleInfo: SettingsModule? {
        guard let moduleID = tab.moduleID else { return nil }
        return dataSource.moduleEntries.first { $0.id == moduleID }
    }

    var body: some View {
        Form {
            // 第一部分：基本开关
            Section {
                Toggle(isOn: $isEnabled) {
                    SettingsRow(
                        title: "启用\(tab.title)",
                        subtitle: "开启后可在 Quick 面板中搜索和使用此插件。",
                        icon: { SettingsRowIcon(systemImage: tab.systemImage) }
                    )
                }
                .onChange(of: isEnabled) { _, newValue in
                    if let modID = tab.moduleID {
                        dataSource.setModuleEnabled(modID, enabled: newValue)
                    }
                }
                Toggle(isOn: $showInLauncher) {
                    SettingsRow(
                        title: "在启动器中显示",
                        subtitle: "搜索时展示该插件的结果项。"
                    )
                }
                .settingsEnabled(isEnabled)
            } header: {
                Text(tab.title)
            }

            // 第二部分：唤醒命令
            Group {
                triggerWordsSection
                shortcutSection
            }
            .settingsEnabled(isEnabled)

            // 第三部分：专属配置项
            Group {
                if let customView = dataSource.makeFeatureSettingsView(for: tab) {
                    customView
                } else {
                    defaultFeatureContent
                }
            }
            .settingsEnabled(isEnabled)
        }
        .formStyle(.grouped)
    }

    /// 触发词列表区域
    @ViewBuilder
    private var triggerWordsSection: some View {
        if let info = moduleInfo, !info.triggerWords.isEmpty {
            Section {
                let chinese = info.triggerWords.filter { $0.containsCJK }
                let english = info.triggerWords.filter { !$0.containsCJK }

                if !chinese.isEmpty {
                    SettingsRow(
                        title: "中文命令",
                        icon: { SettingsRowIcon(systemImage: "character.textbox.zh") }
                    ) {
                        triggerChips(chinese)
                    }
                }

                if !english.isEmpty {
                    SettingsRow(
                        title: "英文命令",
                        icon: { SettingsRowIcon(systemImage: "character.textbox.en") }
                    ) {
                        triggerChips(english)
                    }
                }
            } header: {
                Text("唤醒命令")
            } footer: {
                Text("在搜索框中输入以上任一关键词即可唤醒此插件。")
            }
        }
    }

    /// 触发词标签
    private func triggerChips(_ words: [String]) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(word)
                    .font(DesignTokens.Typography.keyCap)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    /// 快捷键绑定区域
    @ViewBuilder
    private var shortcutSection: some View {
        if let moduleID = tab.moduleID {
            Section {
                SettingsRow(
                    title: "全局快捷键",
                    subtitle: "在任何应用中按下即可打开此插件面板。",
                    icon: { SettingsRowIcon(systemImage: "keyboard") }
                ) {
                    ShortcutRecorder(
                        keycaps: dataSource.moduleShortcutKeycaps(for: moduleID),
                        onRecord: { keyCode, modifiers in
                            dataSource.setModuleShortcut(
                                keyCode: keyCode, carbonModifiers: modifiers, for: moduleID)
                        },
                        onClear: {
                            dataSource.clearModuleShortcut(for: moduleID)
                        }
                    )
                }
            } header: {
                Text("快捷键")
            }
        }
    }

    @ViewBuilder
    private var defaultFeatureContent: some View {
        switch tab {
        case .clipboard:
            ClipboardFeatureSection()
        case .calculator:
            CalculatorFeatureSection()
        case .fileSearch:
            FileSearchFeatureSection()
        case .snippets:
            SnippetsFeatureSection()
        case .windowManagement:
            WindowManagerFeatureSection()
        case .notes:
            NotesFeatureSection()
        case .calendar:
            CalendarFeatureSection()
        case .weather:
            WeatherFeatureSection()
        case .ai:
            AIFeatureSection()
        case .translator:
            TranslatorFeatureSection()
        case .devTools:
            DevToolsFeatureSection()
        case .systemMonitor:
            SystemMonitorFeatureSection()
        case .networkTools:
            NetworkToolsFeatureSection()
        case .ocr:
            OCRFeatureSection()
        case .screenshot:
            ScreenshotFeatureSection()
        default:
            EmptyView()
        }
    }
}

// MARK: - String 扩展

private extension String {
    /// 是否包含 CJK 字符
    var containsCJK: Bool {
        contains { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            return (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
        }
    }
}

// MARK: - 各模块配置子表单

private struct ClipboardFeatureSection: View {
    @AppStorage("clipboard.maxEntries") private var maxEntries = 500
    @AppStorage("clipboard.clearOnQuit") private var clearOnQuit = false
    @AppStorage("clipboard.monitorEnabled") private var monitorEnabled = true
    @AppStorage("clipboard.showPreview") private var showPreview = true
    @AppStorage("clipboard.deduplication") private var deduplication = true

    var body: some View {
        Section {
            Toggle(isOn: $monitorEnabled) {
                SettingsRow(
                    title: "启用剪贴板监听",
                    subtitle: "实时监控系统剪贴板变化并记录历史。关闭后不再自动捕获。",
                    icon: { SettingsRowIcon(systemImage: "eye") }
                )
            }
        } header: {
            Text("监听")
        }

        Section {
            SettingsRow(
                title: "历史记录上限",
                subtitle: "超过上限时自动淘汰最旧的条目。",
                icon: { SettingsRowIcon(systemImage: "tray.full") }
            ) {
                Stepper("\(maxEntries) 条", value: $maxEntries, in: 100...5000, step: 100)
                    .frame(width: 120)
            }

            Toggle(isOn: $deduplication) {
                SettingsRow(
                    title: "自动去重",
                    subtitle: "连续复制相同内容时只保留一条记录。"
                )
            }

            Toggle(isOn: $showPreview) {
                SettingsRow(
                    title: "显示内容预览",
                    subtitle: "在搜索结果中展示剪贴板内容的前几行。"
                )
            }
        } header: {
            Text("历史记录")
        }

        Section {
            Toggle(isOn: $clearOnQuit) {
                SettingsRow(
                    title: "退出时清除历史",
                    subtitle: "关闭 Quick 时自动清空剪贴板历史。适合注重隐私的用户。",
                    icon: { SettingsRowIcon(systemImage: "trash") }
                )
            }
        } header: {
            Text("隐私")
        }
    }
}

private struct CalculatorFeatureSection: View {
    @AppStorage("calculator.precision") private var precision = 4
    @AppStorage("calculator.useGroupingSeparator") private var useGrouping = true
    @AppStorage("calculator.autoCopy") private var autoCopy = false

    var body: some View {
        Section {
            Picker(selection: $precision) {
                Text("2 位").tag(2)
                Text("4 位").tag(4)
                Text("6 位").tag(6)
                Text("完整精度").tag(10)
            } label: {
                SettingsRow(
                    title: "小数位数",
                    subtitle: "计算结果保留的小数位数。",
                    icon: { SettingsRowIcon(systemImage: "number") }
                )
            }

            Toggle(isOn: $useGrouping) {
                SettingsRow(
                    title: "千分位分隔符",
                    subtitle: "大数字显示为 1,000,000 而不是 1000000。"
                )
            }

            Toggle(isOn: $autoCopy) {
                SettingsRow(
                    title: "回车后自动复制结果",
                    subtitle: "按回车确认后将计算结果自动复制到剪贴板。"
                )
            }
        } header: {
            Text("计算偏好")
        }
    }
}

private struct FileSearchFeatureSection: View {
    @AppStorage("fileSearch.ignoreHidden") private var ignoreHidden = true
    @AppStorage("fileSearch.maxResults") private var maxResults = 50
    @AppStorage("fileSearch.includeContents") private var includeContents = false

    var body: some View {
        Section {
            Toggle(isOn: $ignoreHidden) {
                SettingsRow(
                    title: "忽略隐藏文件",
                    subtitle: "不搜索以 . 开头的文件和目录。",
                    icon: { SettingsRowIcon(systemImage: "eye.slash") }
                )
            }

            Toggle(isOn: $includeContents) {
                SettingsRow(
                    title: "搜索文件内容",
                    subtitle: "同时搜索文件内的文本内容（可能较慢）。"
                )
            }

            Picker(selection: $maxResults) {
                Text("20 条").tag(20)
                Text("50 条").tag(50)
                Text("100 条").tag(100)
                Text("200 条").tag(200)
            } label: {
                SettingsRow(
                    title: "最大结果数",
                    subtitle: "单次搜索最多返回的文件数量。"
                )
            }
        } header: {
            Text("搜索规则")
        } footer: {
            Text("文件搜索基于 macOS Spotlight 索引，以「f 」或「文件 」开头触发。")
        }
    }
}

private struct SnippetsFeatureSection: View {
    @AppStorage("snippets.autoExpand") private var autoExpand = true
    @AppStorage("snippets.showSnippetHint") private var showHint = true

    var body: some View {
        Section {
            Toggle(isOn: $autoExpand) {
                SettingsRow(
                    title: "自动展开关键词",
                    subtitle: "键入片段关键词后自动替换为完整内容。",
                    icon: { SettingsRowIcon(systemImage: "text.insert") }
                )
            }

            Toggle(isOn: $showHint) {
                SettingsRow(
                    title: "显示触发提示",
                    subtitle: "在搜索结果中展示片段的触发关键词。"
                )
            }
        } header: {
            Text("展开规则")
        }
    }
}

private struct WindowManagerFeatureSection: View {
    @AppStorage("windowManager.gap") private var gap = 8
    @AppStorage("windowManager.screenMargin") private var margin = 8
    @AppStorage("windowManager.snapOnDrag") private var snapOnDrag = true

    var body: some View {
        Section {
            SettingsRow(
                title: "窗口间距",
                subtitle: "平铺时窗口之间的像素间隙。",
                icon: { SettingsRowIcon(systemImage: "rectangle.split.2x1") }
            ) {
                Stepper("\(gap) px", value: $gap, in: 0...32, step: 2)
                    .frame(width: 100)
            }

            SettingsRow(
                title: "屏幕边距",
                subtitle: "窗口与屏幕边缘的像素间隙。"
            ) {
                Stepper("\(margin) px", value: $margin, in: 0...32, step: 2)
                    .frame(width: 100)
            }

            Toggle(isOn: $snapOnDrag) {
                SettingsRow(
                    title: "拖拽吸附",
                    subtitle: "拖动窗口到屏幕边缘时自动吸附到对应布局。"
                )
            }
        } header: {
            Text("布局选项")
        }
    }
}

private struct NotesFeatureSection: View {
    @AppStorage("notes.autoSave") private var autoSave = true
    @AppStorage("notes.defaultFormat") private var defaultFormat = "plain"

    var body: some View {
        Section {
            Toggle(isOn: $autoSave) {
                SettingsRow(
                    title: "自动保存",
                    subtitle: "编辑内容时实时自动保存，无需手动操作。",
                    icon: { SettingsRowIcon(systemImage: "square.and.arrow.down") }
                )
            }

            Picker(selection: $defaultFormat) {
                Text("纯文本").tag("plain")
                Text("Markdown").tag("markdown")
            } label: {
                SettingsRow(
                    title: "默认格式",
                    subtitle: "新建笔记时的默认文本格式。"
                )
            }
        } header: {
            Text("便签存储")
        }
    }
}

private struct CalendarFeatureSection: View {
    @AppStorage("calendar.reminderMinutes") private var reminderMinutes = 10
    @AppStorage("calendar.autoExtractMeetingLinks") private var autoLinks = true
    @AppStorage("calendar.showWeekNumber") private var showWeekNumber = false

    var body: some View {
        Section {
            Picker(selection: $reminderMinutes) {
                Text("5 分钟").tag(5)
                Text("10 分钟").tag(10)
                Text("15 分钟").tag(15)
                Text("30 分钟").tag(30)
            } label: {
                SettingsRow(
                    title: "提前提醒时间",
                    subtitle: "在日程开始前多久发出通知。",
                    icon: { SettingsRowIcon(systemImage: "bell") }
                )
            }

            Toggle(isOn: $autoLinks) {
                SettingsRow(
                    title: "提取会议链接",
                    subtitle: "自动识别腾讯会议、Zoom、Google Meet 等会议链接。"
                )
            }

            Toggle(isOn: $showWeekNumber) {
                SettingsRow(
                    title: "显示周数",
                    subtitle: "在日历视图中显示当前是第几周。"
                )
            }
        } header: {
            Text("日程与提醒")
        }
    }
}

private struct WeatherFeatureSection: View {
    @AppStorage("weather.defaultCity") private var defaultCity = "自动定位"
    @AppStorage("weather.unit") private var unit = "celsius"
    @AppStorage("weather.showHumidity") private var showHumidity = true

    var body: some View {
        Section {
            Picker(selection: $defaultCity) {
                Text("自动定位").tag("自动定位")
                Text("北京").tag("北京")
                Text("上海").tag("上海")
                Text("深圳").tag("深圳")
                Text("广州").tag("广州")
                Text("杭州").tag("杭州")
                Text("成都").tag("成都")
            } label: {
                SettingsRow(
                    title: "默认城市",
                    subtitle: "不使用定位时显示该城市的天气。",
                    icon: { SettingsRowIcon(systemImage: "building.2") }
                )
            }

            Picker(selection: $unit) {
                Text("摄氏度 (°C)").tag("celsius")
                Text("华氏度 (°F)").tag("fahrenheit")
            } label: {
                SettingsRow(
                    title: "温度单位",
                    subtitle: "天气信息使用的温度计量单位。"
                )
            }

            Toggle(isOn: $showHumidity) {
                SettingsRow(
                    title: "显示湿度",
                    subtitle: "在天气信息中同时展示湿度百分比。"
                )
            }
        } header: {
            Text("天气偏好")
        }
    }
}

private struct AIFeatureSection: View {
    @AppStorage("ai.defaultAlwaysOnTop") private var alwaysOnTop = false

    var body: some View {
        Section {
            SettingsRow(
                title: "AI 聚合门户",
                subtitle: "集成 DeepSeek、ChatGPT、Gemini、Claude、豆包、Kimi、智谱、通义千问等 AI 官网。"
                    + "每个服务在独立窗口中运行，保持登录态。",
                icon: { SettingsRowIcon(systemImage: "sparkles") }
            )
        } header: {
            Text("关于")
        }

        Section {
            Toggle(isOn: $alwaysOnTop) {
                SettingsRow(
                    title: "窗口默认置顶",
                    subtitle: "新打开的 AI 窗口默认悬浮在最前。",
                    icon: { SettingsRowIcon(systemImage: "pin") }
                )
            }
        } header: {
            Text("窗口偏好")
        }

        Section {
            ForEach(aiProviderNames, id: \.id) { item in
                AIProviderToggleRow(id: item.id, name: item.name, icon: item.icon)
            }
        } header: {
            Text("AI 服务")
        } footer: {
            Text("关闭的服务不会出现在搜索结果和聚合面板中。")
        }
    }

    /// 内置 Provider 列表（仅用于设置展示，避免 QuickUI 依赖 ModuleAI）
    private var aiProviderNames: [(id: String, name: String, icon: String)] {
        [
            (id: "deepseek", name: "DeepSeek", icon: "brain.head.profile"),
            (id: "chatgpt", name: "ChatGPT", icon: "bubble.left.and.text.bubble.right"),
            (id: "gemini", name: "Gemini", icon: "sparkle"),
            (id: "claude", name: "Claude", icon: "text.bubble"),
            (id: "doubao", name: "豆包", icon: "leaf"),
            (id: "kimi", name: "Kimi", icon: "moon"),
            (id: "glm", name: "智谱清言", icon: "wand.and.stars"),
            (id: "tongyi", name: "通义千问", icon: "cloud")
        ]
    }
}

/// 单个 AI Provider 的启用/禁用开关行
private struct AIProviderToggleRow: View {
    let id: String
    let name: String
    let icon: String
    @AppStorage var isEnabled: Bool

    init(id: String, name: String, icon: String) {
        self.id = id
        self.name = name
        self.icon = icon
        self._isEnabled = AppStorage(wrappedValue: true, "ai.provider.\(id).enabled")
    }

    var body: some View {
        Toggle(isOn: $isEnabled) {
            SettingsRow(
                title: name,
                icon: { SettingsRowIcon(systemImage: icon) }
            )
        }
    }
}

private struct TranslatorFeatureSection: View {
    @AppStorage("translator.targetLang") private var targetLang = "zh-Hans"
    @AppStorage("translator.autoDetect") private var autoDetect = true

    var body: some View {
        Section {
            Picker(selection: $targetLang) {
                Text("简体中文").tag("zh-Hans")
                Text("繁体中文").tag("zh-Hant")
                Text("英语").tag("en")
                Text("日语").tag("ja")
                Text("韩语").tag("ko")
                Text("法语").tag("fr")
                Text("德语").tag("de")
            } label: {
                SettingsRow(
                    title: "默认目标语言",
                    subtitle: "翻译结果默认输出的语言。",
                    icon: { SettingsRowIcon(systemImage: "globe") }
                )
            }

            Toggle(isOn: $autoDetect) {
                SettingsRow(
                    title: "自动检测源语言",
                    subtitle: "自动识别输入文本的语言，无需手动选择。"
                )
            }
        } header: {
            Text("语言偏好")
        } footer: {
            Text("使用「翻译 <文本>」或「tr <文本>」触发翻译。")
        }
    }
}

private struct DevToolsFeatureSection: View {
    @AppStorage("devTools.jsonIndent") private var jsonIndent = 2
    @AppStorage("devTools.autoFormat") private var autoFormat = true
    @AppStorage("devTools.uppercaseUUID") private var uppercaseUUID = true

    var body: some View {
        Section {
            Picker(selection: $jsonIndent) {
                Text("2 个空格").tag(2)
                Text("4 个空格").tag(4)
                Text("Tab").tag(0)
            } label: {
                SettingsRow(
                    title: "JSON 缩进",
                    subtitle: "格式化 JSON 时使用的缩进风格。",
                    icon: { SettingsRowIcon(systemImage: "curlybraces") }
                )
            }

            Toggle(isOn: $autoFormat) {
                SettingsRow(
                    title: "粘贴时自动格式化",
                    subtitle: "粘贴 JSON/SQL 等内容时自动美化输出。"
                )
            }

            Toggle(isOn: $uppercaseUUID) {
                SettingsRow(
                    title: "UUID 大写",
                    subtitle: "生成 UUID 时使用大写字母（A-F 而非 a-f）。"
                )
            }
        } header: {
            Text("格式化选项")
        }
    }
}

private struct SystemMonitorFeatureSection: View {
    @AppStorage("sysmonitor.interval") private var interval = 2
    @AppStorage("sysmonitor.showMenuBarStats") private var showMenuBar = false

    var body: some View {
        Section {
            Picker(selection: $interval) {
                Text("1 秒").tag(1)
                Text("2 秒").tag(2)
                Text("5 秒").tag(5)
                Text("10 秒").tag(10)
            } label: {
                SettingsRow(
                    title: "刷新周期",
                    subtitle: "系统数据的采样间隔。更短的间隔更实时，但消耗更多资源。",
                    icon: { SettingsRowIcon(systemImage: "timer") }
                )
            }

            Toggle(isOn: $showMenuBar) {
                SettingsRow(
                    title: "菜单栏显示 CPU/内存",
                    subtitle: "在菜单栏图标旁实时展示系统负载。"
                )
            }
        } header: {
            Text("监控设置")
        }
    }
}

private struct NetworkToolsFeatureSection: View {
    @AppStorage("networkTools.pingCount") private var pingCount = 4
    @AppStorage("networkTools.timeout") private var timeout = 5
    @AppStorage("networkTools.showExternalIP") private var showExternalIP = true

    var body: some View {
        Section {
            Picker(selection: $pingCount) {
                Text("3 次").tag(3)
                Text("4 次").tag(4)
                Text("10 次").tag(10)
            } label: {
                SettingsRow(
                    title: "Ping 测试次数",
                    subtitle: "每次 Ping 测试发送的数据包数量。",
                    icon: { SettingsRowIcon(systemImage: "antenna.radiowaves.left.and.right") }
                )
            }

            Picker(selection: $timeout) {
                Text("3 秒").tag(3)
                Text("5 秒").tag(5)
                Text("10 秒").tag(10)
            } label: {
                SettingsRow(
                    title: "超时时间",
                    subtitle: "网络请求超时的等待秒数。"
                )
            }

            Toggle(isOn: $showExternalIP) {
                SettingsRow(
                    title: "显示公网 IP",
                    subtitle: "搜索网络工具时自动展示当前公网 IP。"
                )
            }
        } header: {
            Text("网络诊断")
        }
    }
}

private struct OCRFeatureSection: View {
    @AppStorage("ocr.autoCopy") private var autoCopy = true
    @AppStorage("ocr.language") private var language = "auto"

    var body: some View {
        Section {
            Picker(selection: $language) {
                Text("自动检测").tag("auto")
                Text("简体中文").tag("zh-Hans")
                Text("英语").tag("en")
                Text("日语").tag("ja")
            } label: {
                SettingsRow(
                    title: "识别语言",
                    subtitle: "优先识别的文字语言。自动检测适用于大多数场景。",
                    icon: { SettingsRowIcon(systemImage: "textformat.abc") }
                )
            }

            Toggle(isOn: $autoCopy) {
                SettingsRow(
                    title: "识别后自动复制",
                    subtitle: "OCR 完成后将识别的文字自动复制到剪贴板。"
                )
            }
        } header: {
            Text("文字识别")
        }
    }
}

private struct ScreenshotFeatureSection: View {
    @AppStorage("screenshot.format") private var format = "png"
    @AppStorage("screenshot.includePointer") private var includePointer = false
    @AppStorage("screenshot.saveToDesktop") private var saveToDesktop = true

    var body: some View {
        Section {
            Picker(selection: $format) {
                Text("PNG（无损）").tag("png")
                Text("JPEG（紧凑）").tag("jpeg")
                Text("HEIC（高效）").tag("heic")
            } label: {
                SettingsRow(
                    title: "图片格式",
                    subtitle: "截图保存使用的图片编码格式。",
                    icon: { SettingsRowIcon(systemImage: "photo") }
                )
            }

            Toggle(isOn: $includePointer) {
                SettingsRow(
                    title: "包含鼠标指针",
                    subtitle: "截图时保留鼠标光标的图像。"
                )
            }

            Toggle(isOn: $saveToDesktop) {
                SettingsRow(
                    title: "保存到桌面",
                    subtitle: "截图自动保存到桌面，否则仅复制到剪贴板。"
                )
            }
        } header: {
            Text("截图设置")
        }
    }
}
