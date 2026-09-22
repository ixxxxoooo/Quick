// FeatureSettingsPanes.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 功能插件独立设置页容器
///
/// 每个功能插件的设置页结构：
/// 1. 启用开关
/// 2. 触发词列表（展示中英双语唤醒命令）
/// 3. 全局快捷键绑定（快速打开插件面板）
/// 4. 插件身份的说明（内置插件、日志分类）
/// 5. 插件专属配置项
struct FeatureSettingsPane: View {

    let tab: SettingsTab
    let dataSource: any SettingsDataSource

    @State private var isEnabled: Bool

    init(tab: SettingsTab, dataSource: any SettingsDataSource) {
        self.tab = tab
        self.dataSource = dataSource
        let modID = tab.pluginID ?? ""
        _isEnabled = State(initialValue: dataSource.isPluginEnabled(modID))
    }

    /// 查找当前插件的元信息
    private var pluginInfo: SettingsPlugin? {
        guard let pluginID = tab.pluginID else { return nil }
        return dataSource.pluginEntries.first { $0.id == pluginID }
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
                    if let modID = tab.pluginID {
                        dataSource.setPluginEnabled(modID, enabled: newValue)
                    }
                }
            } header: {
                Text(tab.title)
            }

            // 第二部分：功能说明
            descriptionSection

            // 唤醒词只读展示。快捷键只在「快捷键」页绑定
            Group {
                triggerWordsSection
                commandsSection
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

            // 第四部分：身份说明
            pluginIdentitySection
        }
        .formStyle(.grouped)
    }

    /// 插件功能说明区域
    @ViewBuilder
    private var descriptionSection: some View {
        if let info = pluginInfo, !info.description.isEmpty {
            Section {
                SettingsRow(
                    title: "插件说明",
                    subtitle: info.description,
                    icon: { SettingsRowIcon(systemImage: "info.circle") }
                )
            } header: {
                Text("功能说明")
            }
        }
    }

    /// 触发词列表区域
    @ViewBuilder
    private var triggerWordsSection: some View {
        if let info = pluginInfo, !info.triggerWords.isEmpty {
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

    /// 这个插件对外的命令。绑定快捷键不在本页
    @ViewBuilder
    private var commandsSection: some View {
        let commands = dataSource.pluginCommands(tab.pluginID ?? "")
        if !commands.isEmpty {
            Section {
                ForEach(commands) { command in
                    SettingsRow(
                        title: command.title,
                        subtitle: commandSubtitle(command),
                        icon: {
                            SettingsRowIcon(systemImage: command.icon, isEnabled: command.isInvocationEnabled)
                        }
                    )
                }
            } header: {
                Text("命令")
            } footer: {
                Text("要给其中一条绑快捷键，打开「快捷键」，在插件绑定里写它的关键字。")
            }
        }
    }

    /// 命令行的说明：关键字是唤醒词
    private func commandSubtitle(_ command: SettingsCommandBinding) -> String {
        let words = command.keywords.isEmpty ? command.title : command.keywords.joined(separator: "、")
        if command.isInvocationEnabled {
            return "关键字：\(words)。在主面板输入即可唤醒这个功能。"
        }
        return "关键字：\(words)。已关闭，主搜索和快捷键都不会生效。"
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

    /// 触发词标签
    ///
    /// Quick 目前只支持内置插件 —— 它们和宿主一起编译、一起签名，不加载任何外部代码。
    /// 把这件事写在每个插件的设置页里，是因为「插件」这个词会让人以为能装第三方的：
    /// 与其让用户去别处找安装入口，不如在这里说清楚。
    @ViewBuilder
    private var pluginIdentitySection: some View {
        if let pluginID = tab.pluginID {
            Section {
                SettingsRow(
                    title: "内置插件",
                    subtitle: "与 Quick 一同编译分发，不需要也无法单独安装。",
                    icon: { SettingsRowIcon(systemImage: "shippingbox") }
                ) {
                    Text("内置")
                        .font(DesignTokens.Typography.keyCap)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(
                            RoundedRectangle(
                                cornerRadius: DesignTokens.Radius.barControl, style: .continuous
                            )
                            .fill(Color.accentColor.opacity(0.12))
                        )
                        .foregroundStyle(Color.accentColor)
                }

                SettingsRow(
                    title: "标识",
                    subtitle: "设置存储与日志都用它做键，发布后不会变。",
                    icon: { SettingsRowIcon(systemImage: "number") }
                ) {
                    Text(pluginID)
                        .font(DesignTokens.Typography.code)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("关于")
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
        case .notes:
            NotesFeatureSection()
        case .calendar:
            CalendarFeatureSection()
        case .weather:
            WeatherFeatureSection()
        case .ai:
            EmptyView()
        case .translator:
            TranslatorFeatureSection()
        case .jsonFormatter:
            JSONFormatterFeatureSection()
        case .uuidGenerator:
            UUIDGeneratorFeatureSection()
        case .systemMonitor:
            SystemMonitorFeatureSection()
        case .networkTools:
            NetworkToolsFeatureSection()
        case .ocr:
            OCRFeatureSection()
        case .screenshot:
            ScreenshotFeatureSection()

        case .sqlFormatter:
            SQLFormatterFeatureSection()
        case .base64Codec:
            Base64CodecFeatureSection()
        case .urlCodec:
            URLCodecFeatureSection()
        case .hashCalculator:
            HashCalculatorFeatureSection()
        case .timestampConverter:
            TimestampConverterFeatureSection()
        case .wordCounter:
            WordCounterFeatureSection()
        case .textDiff:
            TextDiffFeatureSection()
        case .markdownPreview:
            MarkdownPreviewFeatureSection()
        case .colorCompare:
            ColorCompareFeatureSection()

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

// MARK: - 各插件配置子表单

private struct ClipboardFeatureSection: View {
    @AppStorage(PluginSettingKey.Clipboard.maxEntries) private var maxEntries = 500
    /// 图片预算以 MB 为单位给用户选，存储层用的是字节
    @AppStorage(PluginSettingKey.Clipboard.imageByteBudget) private var imageBudgetBytes = 256 * 1024 * 1024

    private var imageBudgetMB: Binding<Int> {
        Binding(
            get: { imageBudgetBytes / (1024 * 1024) },
            set: { imageBudgetBytes = $0 * 1024 * 1024 }
        )
    }
    @AppStorage(PluginSettingKey.Clipboard.clearOnQuit) private var clearOnQuit = false
    @AppStorage(PluginSettingKey.Clipboard.monitorEnabled) private var monitorEnabled = true
    @AppStorage(PluginSettingKey.Clipboard.showPreview) private var showPreview = true
    @AppStorage(PluginSettingKey.Clipboard.deduplication) private var deduplication = true

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
                subtitle: "超过上限时自动淘汰最旧的条目。置顶与收藏的条目不受影响。",
                icon: { SettingsRowIcon(systemImage: "tray.full") }
            ) {
                Stepper("\(maxEntries) 条", value: $maxEntries, in: 100...5000, step: 100)
                    .frame(width: 120)
            }

            SettingsRow(
                title: "图片占用上限",
                subtitle: "图片比文字大得多，只限条数挡不住。超出后从最旧的图片开始删。",
                icon: { SettingsRowIcon(systemImage: "photo.stack") }
            ) {
                Picker("", selection: imageBudgetMB) {
                    Text("64 MB").tag(64)
                    Text("128 MB").tag(128)
                    Text("256 MB").tag(256)
                    Text("512 MB").tag(512)
                }
                .labelsHidden()
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
    @AppStorage(PluginSettingKey.Calculator.precision) private var precision = 4
    @AppStorage(PluginSettingKey.Calculator.useGroupingSeparator) private var useGrouping = true
    @AppStorage(PluginSettingKey.Calculator.autoCopy) private var autoCopy = false

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
    @AppStorage(PluginSettingKey.FileSearch.ignoreHidden) private var ignoreHidden = true
    @AppStorage(PluginSettingKey.FileSearch.maxResults) private var maxResults = 50
    @AppStorage(PluginSettingKey.FileSearch.includeContents) private var includeContents = false

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
    @AppStorage(PluginSettingKey.Snippets.autoExpand) private var autoExpand = true
    @AppStorage(PluginSettingKey.Snippets.showSnippetHint) private var showHint = true

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

private struct NotesFeatureSection: View {
    @AppStorage(PluginSettingKey.Notes.autoSave) private var autoSave = true
    @AppStorage(PluginSettingKey.Notes.defaultFormat) private var defaultFormat = "plain"

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
        } footer: {
            PendingFeatureNote(detail: "「默认格式」还没有实现：笔记模型里没有格式字段。「自动保存」一直是开着的，关掉它也不会变成手动保存。")
        }
        .disabled(true)
    }
}

private struct CalendarFeatureSection: View {
    @AppStorage(PluginSettingKey.Calendar.reminderMinutes) private var reminderMinutes = 10
    @AppStorage(PluginSettingKey.Calendar.autoExtractMeetingLinks) private var autoLinks = true
    @AppStorage(PluginSettingKey.Calendar.showWeekNumber) private var showWeekNumber = false

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
        } footer: {
            PendingFeatureNote(detail: "这三项还没有实现：EventKit 只用来读日程，提醒、会议链接提取和周数都还没有接上。")
        }
        .disabled(true)
    }
}

private struct WeatherFeatureSection: View {
    @AppStorage(PluginSettingKey.Weather.defaultCity) private var defaultCity = "自动定位"
    @AppStorage(PluginSettingKey.Weather.unit) private var unit = "celsius"
    @AppStorage(PluginSettingKey.Weather.showHumidity) private var showHumidity = true

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
        } footer: {
            PendingFeatureNote(detail: "这三项还没有实现：天气服务目前是占位实现（未接入 WeatherKit），返回的是固定内容。")
        }
        .disabled(true)
    }
}

private struct TranslatorFeatureSection: View {
    @AppStorage(PluginSettingKey.Translator.targetLang) private var targetLang = "zh-Hans"
    @AppStorage(PluginSettingKey.Translator.autoDetect) private var autoDetect = true

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

/// JSON 格式化的专属选项
///
/// 键与 `JSONFormatterView` 里的 `@AppStorage` 是同一个 —— 这里改的就是工具面板里那一项，
/// 两边读写同一份值，不存在「设置里能调但工具不理会」的假开关。
private struct JSONFormatterFeatureSection: View {
    @AppStorage(PluginSettingKey.JSONFormatter.indent) private var indent = 2

    var body: some View {
        Section {
            Picker(selection: $indent) {
                Text("2 个空格").tag(2)
                Text("4 个空格").tag(4)
            } label: {
                SettingsRow(
                    title: "缩进风格",
                    subtitle: "格式化 JSON 时的缩进宽度。",
                    icon: { SettingsRowIcon(systemImage: "curlybraces") }
                )
            }
        } header: {
            Text("格式化选项")
        } footer: {
            Text("「压缩」不受此设置影响，它总是输出单行。")
        }
    }
}

/// UUID 生成器的专属选项
private struct UUIDGeneratorFeatureSection: View {
    @AppStorage(PluginSettingKey.UUIDGenerator.uppercase) private var uppercase = true
    @AppStorage(PluginSettingKey.UUIDGenerator.removeDashes) private var removeDashes = false

    var body: some View {
        Section {
            Toggle(isOn: $uppercase) {
                SettingsRow(
                    title: "大写字母",
                    subtitle: "生成 A-F 而不是 a-f。",
                    icon: { SettingsRowIcon(systemImage: "textformat") }
                )
            }

            Toggle(isOn: $removeDashes) {
                SettingsRow(
                    title: "去掉连字符",
                    subtitle: "输出 32 位连续字符串，适合直接当数据库主键。"
                )
            }
        } header: {
            Text("生成格式")
        } footer: {
            Text("数量在插件面板里按次选择，不在这里固定。")
        }
    }
}

private struct SystemMonitorFeatureSection: View {
    @AppStorage(PluginSettingKey.SystemMonitor.interval) private var interval = 2
    @AppStorage(PluginSettingKey.SystemMonitor.showMenuBarStats) private var showMenuBar = false

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
            .disabled(true)
        } header: {
            Text("监控设置")
        } footer: {
            PendingFeatureNote(detail: "「菜单栏显示 CPU/内存」还没有实现：插件面板里的采样是真的，菜单栏那块还没接。")
        }
    }
}

private struct NetworkToolsFeatureSection: View {
    @AppStorage(PluginSettingKey.NetworkTools.pingCount) private var pingCount = 4
    @AppStorage(PluginSettingKey.NetworkTools.timeout) private var timeout = 5
    @AppStorage(PluginSettingKey.NetworkTools.showExternalIP) private var showExternalIP = true

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
        } footer: {
            PendingFeatureNote(detail: "Ping 测试次数与超时还没有实现：这个插件目前只做本机地址、DNS 和公网 IP，没有 ping 功能。")
        }
    }
}

private struct OCRFeatureSection: View {
    @AppStorage(PluginSettingKey.OCR.autoCopy) private var autoCopy = true
    @AppStorage(PluginSettingKey.OCR.language) private var language = "auto"

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
    @AppStorage(PluginSettingKey.Screenshot.format) private var format = "png"
    @AppStorage(PluginSettingKey.Screenshot.includePointer) private var includePointer = false
    @AppStorage(PluginSettingKey.Screenshot.saveToDesktop) private var saveToDesktop = true

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

// MARK: - 独立开发者工具设置子表单

private struct SQLFormatterFeatureSection: View {
    @AppStorage(PluginSettingKey.SQLFormatter.keywordCase) private var keywordCase = "uppercase"
    @AppStorage(PluginSettingKey.SQLFormatter.indent) private var indent = 2

    var body: some View {
        Section {
            Picker(selection: $keywordCase) {
                Text("大写 (UPPERCASE)").tag("uppercase")
                Text("小写 (lowercase)").tag("lowercase")
            } label: {
                SettingsRow(
                    title: "关键字大小写",
                    subtitle: "格式化时 SELECT、FROM 等 SQL 关键字的风格。",
                    icon: { SettingsRowIcon(systemImage: "textformat") }
                )
            }

            Picker(selection: $indent) {
                Text("2 个空格").tag(2)
                Text("4 个空格").tag(4)
            } label: {
                SettingsRow(
                    title: "缩进宽度",
                    subtitle: "每层子查询与表达式的缩进空格数。",
                    icon: { SettingsRowIcon(systemImage: "increase.indent") }
                )
            }
        } header: {
            Text("SQL 格式化选项")
        }
    }
}

private struct Base64CodecFeatureSection: View {
    @AppStorage(PluginSettingKey.Base64Codec.urlSafe) private var urlSafe = false
    @AppStorage(PluginSettingKey.Base64Codec.wrapLines) private var wrapLines = false

    var body: some View {
        Section {
            Toggle(isOn: $urlSafe) {
                SettingsRow(
                    title: "URL 安全模式 (URL-Safe)",
                    subtitle: "将字符 +/ 替换为 -_，且省略尾部填充 =，适用于 URL 传参。",
                    icon: { SettingsRowIcon(systemImage: "shield") }
                )
            }

            Toggle(isOn: $wrapLines) {
                SettingsRow(
                    title: "自动换行",
                    subtitle: "编码长数据时每 76 个字符自动插入换行符。",
                    icon: { SettingsRowIcon(systemImage: "text.alignleft") }
                )
            }
        } header: {
            Text("编解码规则")
        }
    }
}

private struct URLCodecFeatureSection: View {
    @AppStorage(PluginSettingKey.URLCodec.encodeSpacesAsPluses) private var spacesAsPluses = false
    @AppStorage(PluginSettingKey.URLCodec.encodeFullUrl) private var encodeFullUrl = false

    var body: some View {
        Section {
            Toggle(isOn: $spacesAsPluses) {
                SettingsRow(
                    title: "空格编码为加号 (+)",
                    subtitle: "关闭时使用标准的 %20，开启后符合 application/x-www-form-urlencoded 规范。",
                    icon: { SettingsRowIcon(systemImage: "plus") }
                )
            }

            Toggle(isOn: $encodeFullUrl) {
                SettingsRow(
                    title: "完整 URL 模式",
                    subtitle: "保留 :// 等协议分隔符，仅对查询参数与路径非保留字符编码。",
                    icon: { SettingsRowIcon(systemImage: "link") }
                )
            }
        } header: {
            Text("URL 编码选项")
        }
    }
}

private struct HashCalculatorFeatureSection: View {
    @AppStorage(PluginSettingKey.HashCalculator.uppercase) private var uppercase = false
    @AppStorage(PluginSettingKey.HashCalculator.autoCopy) private var autoCopy = false

    var body: some View {
        Section {
            Toggle(isOn: $uppercase) {
                SettingsRow(
                    title: "十六进制大写显示",
                    subtitle: "输出 A-F 而非默认的小写 a-f 散列值。",
                    icon: { SettingsRowIcon(systemImage: "textformat") }
                )
            }

            Toggle(isOn: $autoCopy) {
                SettingsRow(
                    title: "计算后自动复制",
                    subtitle: "输入文本后自动把首选 SHA-256 散列结果复制到剪贴板。",
                    icon: { SettingsRowIcon(systemImage: "doc.on.clipboard") }
                )
            }
        } header: {
            Text("计算与输出")
        }
    }
}

private struct TimestampConverterFeatureSection: View {
    @AppStorage(PluginSettingKey.TimestampConverter.defaultUnit) private var defaultUnit = "seconds"
    @AppStorage(PluginSettingKey.TimestampConverter.timeZone) private var timeZone = "local"

    var body: some View {
        Section {
            Picker(selection: $defaultUnit) {
                Text("秒 (10 位)").tag("seconds")
                Text("毫秒 (13 位)").tag("milliseconds")
            } label: {
                SettingsRow(
                    title: "默认时间戳单位",
                    subtitle: "生成当前时间戳时使用的默认精度单位。",
                    icon: { SettingsRowIcon(systemImage: "clock") }
                )
            }

            Picker(selection: $timeZone) {
                Text("本地时区 (Local)").tag("local")
                Text("协调世界时 (UTC)").tag("utc")
            } label: {
                SettingsRow(
                    title: "默认时区",
                    subtitle: "格式化输出可读日期文本时使用的参考时区。",
                    icon: { SettingsRowIcon(systemImage: "globe") }
                )
            }
        } header: {
            Text("转换偏好")
        }
    }
}

private struct WordCounterFeatureSection: View {
    @AppStorage(PluginSettingKey.WordCounter.ignoreWhitespace) private var ignoreWhitespace = false
    @AppStorage(PluginSettingKey.WordCounter.readingSpeedWPM) private var readingSpeed = 300

    var body: some View {
        Section {
            Toggle(isOn: $ignoreWhitespace) {
                SettingsRow(
                    title: "字符统计忽略空白符",
                    subtitle: "统计总字数时不计入空格、制表符与换行符。",
                    icon: { SettingsRowIcon(systemImage: "character") }
                )
            }

            Picker(selection: $readingSpeed) {
                Text("200 字/分（沉浸阅读）").tag(200)
                Text("300 字/分（标准阅读）").tag(300)
                Text("400 字/分（快速浏览）").tag(400)
            } label: {
                SettingsRow(
                    title: "预估阅读速度",
                    subtitle: "用于估算文本所需阅读时长。",
                    icon: { SettingsRowIcon(systemImage: "speedometer") }
                )
            }
        } header: {
            Text("统计规则")
        }
    }
}

private struct TextDiffFeatureSection: View {
    @AppStorage(PluginSettingKey.TextDiff.ignoreWhitespace) private var ignoreWhitespace = false
    @AppStorage(PluginSettingKey.TextDiff.ignoreCase) private var ignoreCase = false

    var body: some View {
        Section {
            Toggle(isOn: $ignoreWhitespace) {
                SettingsRow(
                    title: "忽略空白字符差异",
                    subtitle: "比对文本时忽略行首行尾空格与换行符的变动。",
                    icon: { SettingsRowIcon(systemImage: "space") }
                )
            }

            Toggle(isOn: $ignoreCase) {
                SettingsRow(
                    title: "忽略大小写差异",
                    subtitle: "比对英文字符时不区分大写与小写。",
                    icon: { SettingsRowIcon(systemImage: "textformat.size") }
                )
            }
        } header: {
            Text("文本比对选项")
        }
    }
}

private struct MarkdownPreviewFeatureSection: View {
    @AppStorage(PluginSettingKey.MarkdownPreview.showLineNumbers) private var showLineNumbers = true
    @AppStorage(PluginSettingKey.MarkdownPreview.enableMathJax) private var enableMathJax = true

    var body: some View {
        Section {
            Toggle(isOn: $showLineNumbers) {
                SettingsRow(
                    title: "代码块显示行号",
                    subtitle: "在渲染的代码语法高亮区块左侧显示代码行号。",
                    icon: { SettingsRowIcon(systemImage: "list.number") }
                )
            }

            Toggle(isOn: $enableMathJax) {
                SettingsRow(
                    title: "启用数学公式渲染 (LaTeX)",
                    subtitle: "自动识别并渲染 $...$ 与 $$...$$ 内的数学公式。",
                    icon: { SettingsRowIcon(systemImage: "function") }
                )
            }
        } header: {
            Text("Markdown 渲染")
        }
    }
}

private struct ColorCompareFeatureSection: View {
    @AppStorage(PluginSettingKey.ColorCompare.defaultFormat) private var defaultFormat = "hex"
    @AppStorage(PluginSettingKey.ColorCompare.uppercaseHex) private var uppercaseHex = true

    var body: some View {
        Section {
            Picker(selection: $defaultFormat) {
                Text("十六进制 (HEX)").tag("hex")
                Text("RGB 格式").tag("rgb")
                Text("HSL 格式").tag("hsl")
            } label: {
                SettingsRow(
                    title: "默认色彩格式",
                    subtitle: "复制颜色代码时的优先格式。",
                    icon: { SettingsRowIcon(systemImage: "paintpalette") }
                )
            }

            Toggle(isOn: $uppercaseHex) {
                SettingsRow(
                    title: "HEX 字母大写",
                    subtitle: "生成 #FFFFFF 而不是小写的 #ffffff。",
                    icon: { SettingsRowIcon(systemImage: "textformat") }
                )
            }
        } header: {
            Text("颜色格式")
        }
    }
}
