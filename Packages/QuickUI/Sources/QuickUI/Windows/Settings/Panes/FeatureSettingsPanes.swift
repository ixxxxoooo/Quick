// FeatureSettingsPanes.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 功能模块独立设置页容器
///
/// 参考 Tinycast 设计：
/// - 每个功能模块都有专属的独立设置页
/// - 顶部为统一的「启用该功能」开关
/// - 包含各模块专属的功能参数卡片
/// - 若模块通过 QuickModule.makeSettingsView() 提供了自定义视图，则优先嵌入展示
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

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $isEnabled) {
                    Text("Enable \(tab.title.lowercased())")
                    Text("Enable the \(tab.title.lowercased()) feature in Quick.")
                }
                .onChange(of: isEnabled) { _, newValue in
                    if let modID = tab.moduleID {
                        dataSource.setModuleEnabled(modID, enabled: newValue)
                    }
                }
                Toggle(isOn: $showInLauncher) {
                    Text("Show in launcher")
                    Text("Find \(tab.title.lowercased()) items in launcher search.")
                }
                .settingsEnabled(isEnabled)
            } header: {
                Text(tab.title)
            }

            // 专属配置项
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

// MARK: - 各模块配置子表单

private struct ClipboardFeatureSection: View {
    @AppStorage("clipboard.maxEntries") private var maxEntries = 500
    @AppStorage("clipboard.clearOnQuit") private var clearOnQuit = false

    var body: some View {
        Section("历史记录选项") {
            Stepper("历史记录上限：\(maxEntries) 条", value: $maxEntries, in: 100...2000, step: 100)
            Toggle("退出 Quick 时清除历史记录", isOn: $clearOnQuit)
        }
    }
}

private struct CalculatorFeatureSection: View {
    @AppStorage("calculator.precision") private var precision = 4
    @AppStorage("calculator.useGroupingSeparator") private var useGrouping = true

    var body: some View {
        Section("计算偏好") {
            Picker("结果保留小数位数", selection: $precision) {
                Text("2 位").tag(2)
                Text("4 位").tag(4)
                Text("6 位").tag(6)
                Text("完整精度").tag(10)
            }
            Toggle("使用千分位分隔符 (1,000)", isOn: $useGrouping)
        }
    }
}

private struct FileSearchFeatureSection: View {
    @AppStorage("fileSearch.ignoreHidden") private var ignoreHidden = true
    @AppStorage("fileSearch.maxResults") private var maxResults = 50

    var body: some View {
        Section("搜索规则") {
            Toggle("忽略隐藏文件与目录", isOn: $ignoreHidden)
            Picker("最多返回结果数", selection: $maxResults) {
                Text("20 条").tag(20)
                Text("50 条").tag(50)
                Text("100 条").tag(100)
            }
        }
    }
}

private struct SnippetsFeatureSection: View {
    @AppStorage("snippets.autoExpand") private var autoExpand = true

    var body: some View {
        Section("展开规则") {
            Toggle("键入关键词后自动展开", isOn: $autoExpand)
        }
    }
}

private struct WindowManagerFeatureSection: View {
    @AppStorage("windowManager.gap") private var gap = 8
    @AppStorage("windowManager.screenMargin") private var margin = 8

    var body: some View {
        Section("窗口布局间距") {
            Stepper("窗口之间留白间隙：\(gap) 像素", value: $gap, in: 0...32, step: 2)
            Stepper("屏幕外边缘留白：\(margin) 像素", value: $margin, in: 0...32, step: 2)
        }
    }
}

private struct NotesFeatureSection: View {
    @AppStorage("notes.autoSave") private var autoSave = true

    var body: some View {
        Section("便签存储") {
            Toggle("内容变动时实时自动保存", isOn: $autoSave)
        }
    }
}

private struct CalendarFeatureSection: View {
    @AppStorage("calendar.reminderMinutes") private var reminderMinutes = 10
    @AppStorage("calendar.autoExtractMeetingLinks") private var autoLinks = true

    var body: some View {
        Section("日程提醒") {
            Picker("临近会议提前提醒时间", selection: $reminderMinutes) {
                Text("5 分钟").tag(5)
                Text("10 分钟").tag(10)
                Text("15 分钟").tag(15)
            }
            Toggle("自动提取腾讯会议/Zoom/Google Meet 会议链接", isOn: $autoLinks)
        }
    }
}

private struct WeatherFeatureSection: View {
    @AppStorage("weather.defaultCity") private var defaultCity = "自动定位"
    @AppStorage("weather.unit") private var unit = "celsius"

    var body: some View {
        Section("天气偏好") {
            Picker("默认城市", selection: $defaultCity) {
                Text("自动定位").tag("自动定位")
                Text("北京").tag("北京")
                Text("上海").tag("上海")
                Text("深圳").tag("深圳")
                Text("广州").tag("广州")
                Text("杭州").tag("杭州")
            }
            Picker("温度单位", selection: $unit) {
                Text("摄氏度 (°C)").tag("celsius")
                Text("华氏度 (°F)").tag("fahrenheit")
            }
        }
    }
}

private struct AIFeatureSection: View {
    @AppStorage("ai.defaultModel") private var model = "gpt-4o"
    @AppStorage("ai.apiEndpoint") private var endpoint = ""

    var body: some View {
        Section("模型与接口") {
            Picker("默认推理模型", selection: $model) {
                Text("GPT-4o").tag("gpt-4o")
                Text("Claude 3.5 Sonnet").tag("claude-3-5-sonnet")
                Text("DeepSeek V3").tag("deepseek-v3")
            }
            TextField("自定义 API Endpoint（可选）", text: $endpoint)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct TranslatorFeatureSection: View {
    @AppStorage("translator.targetLang") private var targetLang = "zh-Hans"

    var body: some View {
        Section("语言偏好") {
            Picker("默认目标语言", selection: $targetLang) {
                Text("简体中文").tag("zh-Hans")
                Text("英语 (English)").tag("en")
                Text("日语 (日本語)").tag("ja")
            }
        }
    }
}

private struct DevToolsFeatureSection: View {
    @AppStorage("devTools.jsonIndent") private var jsonIndent = 2

    var body: some View {
        Section("格式化选项") {
            Picker("JSON 缩进空格数", selection: $jsonIndent) {
                Text("2 个空格").tag(2)
                Text("4 个空格").tag(4)
            }
        }
    }
}

private struct SystemMonitorFeatureSection: View {
    @AppStorage("sysmonitor.interval") private var interval = 2

    var body: some View {
        Section("监控刷新频率") {
            Picker("刷新周期", selection: $interval) {
                Text("1 秒").tag(1)
                Text("2 秒").tag(2)
                Text("5 秒").tag(5)
            }
        }
    }
}

private struct NetworkToolsFeatureSection: View {
    @AppStorage("networkTools.pingCount") private var pingCount = 4

    var body: some View {
        Section("网络诊断") {
            Picker("默认 Ping 测试包数量", selection: $pingCount) {
                Text("3 次").tag(3)
                Text("4 次").tag(4)
                Text("10 次").tag(10)
            }
        }
    }
}

private struct OCRFeatureSection: View {
    @AppStorage("ocr.autoCopy") private var autoCopy = true

    var body: some View {
        Section("文字识别") {
            Toggle("识别完成后自动复制到剪贴板", isOn: $autoCopy)
        }
    }
}

private struct ScreenshotFeatureSection: View {
    @AppStorage("screenshot.format") private var format = "png"

    var body: some View {
        Section("截图保存格式") {
            Picker("图片格式", selection: $format) {
                Text("PNG (无损)").tag("png")
                Text("JPEG (紧凑)").tag("jpeg")
            }
        }
    }
}
