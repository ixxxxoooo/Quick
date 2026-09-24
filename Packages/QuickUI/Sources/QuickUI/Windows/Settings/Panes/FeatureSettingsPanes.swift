// FeatureSettingsPanes.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 功能插件独立设置页容器
///
/// 每个功能插件的设置页只有三块，且互不重复：
/// 1. 概览：启用开关 + 一句话简介
/// 2. 专属配置项
/// 3. 触发关键字：按功能拆开，每个功能展示自己的关键字
struct FeatureSettingsPane: View {

    let tab: SettingsTab
    let dataSource: any PluginSettingsDataSource & CommandSettingsDataSource

    @State private var isEnabled: Bool

    init(tab: SettingsTab, dataSource: any PluginSettingsDataSource & CommandSettingsDataSource) {
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
            overviewSection
            featureSection
            wakeSection
        }
        .formStyle(.grouped)
    }

    // MARK: - 概览

    /// 启用开关 + 简介
    ///
    /// 不设分组标题：窗口标题与侧边栏已经写着插件名，这里再重复一遍就是噪音。
    private var overviewSection: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                SettingsRow(
                    title: "启用此插件",
                    subtitle: "开启后可在主面板搜索并使用。",
                    icon: {
                        SettingsRowIcon(
                            systemImage: tab.systemImage,
                            tint: .named(tab.iconTintName)
                        )
                    }
                )
            }
            .onChange(of: isEnabled) { _, newValue in
                if let modID = tab.pluginID {
                    dataSource.setPluginEnabled(modID, enabled: newValue)
                }
            }

            if let description = pluginInfo?.description, !description.isEmpty {
                SettingsRow(
                    title: "简介",
                    subtitle: description,
                    icon: { SettingsRowIcon(systemImage: "info.circle") }
                )
            }
        }
    }

    // MARK: - 专属配置

    /// 插件自己的设置项；插件关闭时整体置灰
    @ViewBuilder
    private var featureSection: some View {
        Group {
            if let customView = dataSource.makeFeatureSettingsView(for: tab) {
                customView
            } else {
                defaultFeatureContent
            }
        }
        .settingsEnabled(isEnabled)
    }

    // MARK: - 触发关键字

    /// 触发关键字：按功能拆开，每个功能一行 + 它自己的关键字胶囊
    ///
    /// 插件默认的「打开本插件」命令不单列 —— 它的关键字就是插件的唤醒词，和下面的
    /// 功能关键字重复，单列只是噪音。没有声明任何功能（命令）的插件，这一节整体不显示。
    @ViewBuilder
    private var wakeSection: some View {
        let commands = extraCommands.filter { !displayKeywords($0.keywords).isEmpty }
        if !commands.isEmpty {
            Section {
                ForEach(commands) { command in
                    SettingsRow(
                        title: command.title,
                        subtitle: command.subtitle,
                        trailingPlacement: .below,
                        icon: {
                            SettingsRowIcon(
                                systemImage: command.icon,
                                isEnabled: command.isInvocationEnabled)
                        }
                    ) {
                        triggerChips(displayKeywords(command.keywords))
                    }
                }
            } header: {
                Text("触发关键字")
            } footer: {
                Text("在主面板输入某个功能的关键字即可直接触发它；要给某条命令绑快捷键，到「快捷键」页添加。")
            }
        }
    }

    /// 除默认「打开本插件」之外的命令
    private var extraCommands: [SettingsCommandBinding] {
        guard let pluginID = tab.pluginID else { return [] }
        let openCommandID = CommandID.openPlugin(pluginID)
        return dataSource.pluginCommands(pluginID).filter { $0.id != openCommandID }
    }

    /// 展示用的关键字：命令关键字不带空格，带空格的直接不显示；并去重
    private func displayKeywords(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        return keywords.filter { word in
            !word.isEmpty
                && !word.contains(where: { $0.isWhitespace })
                && seen.insert(word.lowercased()).inserted
        }
    }

    /// 关键字标签：一行放不下就换行，标签内部不换行
    private func triggerChips(_ words: [String]) -> some View {
        FlowLayout(horizontalSpacing: DesignTokens.Spacing.sm, verticalSpacing: DesignTokens.Spacing.xs) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(word)
                    .font(DesignTokens.Typography.keyCap)
                    .lineLimit(1)
                    .fixedSize()
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
        case .killProcess:
            KillProcessFeatureSection()
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

private struct TranslatorFeatureSection: View {
    @AppStorage(PluginSettingKey.Translator.targetLang) private var targetLang = "zh-Hans"

    /// 与插件里的 `TranslationLanguages.all` 保持一致（QuickUI 不认识插件，只能并列一份）
    private static let languages: [(code: String, label: String)] = [
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁体中文"),
        ("en", "英语"),
        ("ja", "日语"),
        ("ko", "韩语"),
        ("fr", "法语"),
        ("de", "德语"),
        ("es", "西班牙语"),
        ("ru", "俄语"),
        ("it", "意大利语"),
        ("pt", "葡萄牙语"),
        ("ar", "阿拉伯语"),
        ("th", "泰语"),
        ("vi", "越南语")
    ]

    var body: some View {
        Section {
            Picker(selection: $targetLang) {
                ForEach(Self.languages, id: \.code) { language in
                    Text(language.label).tag(language.code)
                }
            } label: {
                SettingsRow(
                    title: "默认目标语言",
                    subtitle: "翻译结果默认输出的语言。源语言在插件面板里切换，默认自动识别。",
                    icon: { SettingsRowIcon(systemImage: "globe") }
                )
            }
        } header: {
            Text("语言偏好")
        } footer: {
            Text(
                "在面板里输入「翻译 <文本>」或「translate <文本>」翻译；输入「词典 <单词>」或「dict <单词>」查词。翻译在端上完成，不联网。"
            )
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
    @AppStorage(PluginSettingKey.SystemMonitor.defaultTab) private var defaultTab = "system-info"
    @AppStorage(PluginSettingKey.SystemMonitor.displayModeCPU) private var cpuMode = "used"
    @AppStorage(PluginSettingKey.SystemMonitor.displayModeMemory) private var memoryMode = "used"
    @AppStorage(PluginSettingKey.SystemMonitor.displayModeDisk) private var diskMode = "free"
    @AppStorage(PluginSettingKey.SystemMonitor.displayModeBattery) private var batteryMode = "free"
    @AppStorage(PluginSettingKey.SystemMonitor.showMenuBarStats) private var showMenuBar = false

    var body: some View {
        Section {
            Picker(selection: $defaultTab) {
                Text("系统信息").tag("system-info")
                Text("CPU").tag("cpu")
                Text("内存").tag("memory")
                Text("磁盘").tag("disk")
                Text("电源").tag("power")
                Text("网络").tag("network")
                Text("温度").tag("temperature")
            } label: {
                SettingsRow(
                    title: "默认标签",
                    subtitle: "打开系统监控时默认选中的视图。",
                    icon: { SettingsRowIcon(systemImage: "rectangle.split.2x1") }
                )
            }

            Picker(selection: $cpuMode) {
                Text("显示已用").tag("used")
                Text("显示空闲").tag("free")
            } label: {
                SettingsRow(
                    title: "CPU 显示模式",
                    subtitle: "侧栏与详情里的 CPU 百分比按已用或空闲展示。",
                    icon: { SettingsRowIcon(systemImage: "cpu") }
                )
            }

            Picker(selection: $memoryMode) {
                Text("显示已用").tag("used")
                Text("显示空闲").tag("free")
            } label: {
                SettingsRow(
                    title: "内存显示模式",
                    subtitle: "侧栏与详情里的内存百分比按已用或空闲展示。"
                )
            }

            Picker(selection: $diskMode) {
                Text("显示已用").tag("used")
                Text("显示空闲").tag("free")
            } label: {
                SettingsRow(
                    title: "磁盘显示模式",
                    subtitle: "侧栏与详情里的磁盘百分比按已用或空闲展示。"
                )
            }

            Picker(selection: $batteryMode) {
                Text("显示已用").tag("used")
                Text("显示空闲").tag("free")
            } label: {
                SettingsRow(
                    title: "电池显示模式",
                    subtitle: "有内置电池时，按剩余或已用展示电量。"
                )
            }

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
            Text("配置")
        } footer: {
            PendingFeatureNote(detail: "「菜单栏显示 CPU/内存」还没有实现：面板内采样已就绪，菜单栏文案尚未接线。")
        }
    }
}

private struct KillProcessFeatureSection: View {
    @AppStorage(PluginSettingKey.KillProcess.sortMode) private var sortMode = "cpu"
    @AppStorage(PluginSettingKey.KillProcess.refreshInterval) private var refreshInterval = 3
    @AppStorage(PluginSettingKey.KillProcess.showPID) private var showPID = false
    @AppStorage(PluginSettingKey.KillProcess.searchInPath) private var searchInPath = false
    @AppStorage(PluginSettingKey.KillProcess.searchInPID) private var searchInPID = false

    var body: some View {
        Section {
            Picker(selection: $sortMode) {
                Text("CPU").tag("cpu")
                Text("内存").tag("memory")
            } label: {
                SettingsRow(
                    title: "默认排序",
                    subtitle: "打开结束进程时按 CPU 或内存占用排序。",
                    icon: { SettingsRowIcon(systemImage: "arrow.up.arrow.down") }
                )
            }

            Picker(selection: $refreshInterval) {
                Text("1 秒").tag(1)
                Text("2 秒").tag(2)
                Text("3 秒").tag(3)
                Text("5 秒").tag(5)
                Text("10 秒").tag(10)
            } label: {
                SettingsRow(
                    title: "刷新周期",
                    subtitle: "进程列表的自动刷新间隔。",
                    icon: { SettingsRowIcon(systemImage: "timer") }
                )
            }

            Toggle(isOn: $showPID) {
                SettingsRow(
                    title: "显示 PID",
                    subtitle: "在进程名下方显示进程号。"
                )
            }

            Toggle(isOn: $searchInPath) {
                SettingsRow(
                    title: "搜索可执行路径",
                    subtitle: "标题栏搜索时同时匹配完整路径。"
                )
            }

            Toggle(isOn: $searchInPID) {
                SettingsRow(
                    title: "搜索 PID",
                    subtitle: "标题栏搜索时同时匹配进程号。"
                )
            }
        } header: {
            Text("配置")
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
