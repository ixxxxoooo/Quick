// PluginsPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 插件开关
///
/// 插件数量较多时一屏放不下，所以顶部有一个筛选框（参考实现的做法：
/// 长列表上方给一个搜索框，而不是让用户自己滚）。
struct PluginsPane: View {

    let dataSource: any SettingsDataSource

    @State private var enabledPlugins: [String: Bool]
    @State private var filter = ""
    @State private var selectedPluginID: String?
    @FocusState private var filterFocused: Bool

    init(dataSource: any SettingsDataSource) {
        self.dataSource = dataSource
        _enabledPlugins = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: dataSource.pluginEntries.map {
                    ($0.id, dataSource.isPluginEnabled($0.id))
                }
            )
        )
    }

    /// 按筛选词过滤后的插件
    private var visiblePlugins: [SettingsPlugin] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return dataSource.pluginEntries }
        return dataSource.pluginEntries.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var disabledCount: Int {
        enabledPlugins.values.filter { !$0 }.count
    }

    var body: some View {
        Form {
            Section {
                SettingsFilterField(prompt: "筛选插件", query: $filter, isFocused: $filterFocused)
            }

            Section {
                if visiblePlugins.isEmpty {
                    SettingsRow(title: "没有匹配的插件", subtitle: "换个关键词试试")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visiblePlugins) { plugin in
                        HStack {
                            Toggle(isOn: binding(for: plugin.id)) {
                                SettingsRow(
                                    title: plugin.name,
                                    subtitle: "plugin.\(plugin.id)",
                                    icon: {
                                        SettingsRowIcon(
                                            systemImage: plugin.icon,
                                            isEnabled: enabledPlugins[plugin.id] ?? true
                                        )
                                    }
                                ) {
                                    builtInBadge
                                }
                            }
                            Button("选项") {
                                selectedPluginID = plugin.id
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("插件")
            } footer: {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    if disabledCount > 0 {
                        Text("已停用 \(disabledCount) 个插件。停用的插件不会被搜索到，也不会在启动时加载。")
                    } else {
                        Text("停用的插件不会被搜索到，也不会在启动时加载。")
                    }
                    // 说清楚边界：这里没有安装入口，因为当前版本不加载外部代码
                    Text(
                        "Quick 目前只支持内置插件：它们与宿主一同编译、一同签名，"
                            + "因此不会出现来源不明的代码在后台运行。"
                    )
                }
            }
            if let selected = dataSource.pluginEntries.first(where: { $0.id == selectedPluginID }) {
                PluginOptionsPane(plugin: selected, dataSource: dataSource)
            }
        }
        .formStyle(.grouped)
    }

    /// 每行的「内置」徽章
    private var builtInBadge: some View {
        Text("内置")
            .font(DesignTokens.Typography.keyCap)
            .foregroundStyle(DesignTokens.Colors.textTertiary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                    .fill(DesignTokens.Colors.controlSurface)
            )
    }

    /// 单个插件的开关绑定
    ///
    /// 写回时同时更新本地状态与数据源：本地状态让开关立刻响应，
    /// 数据源负责持久化并同步插件实例。
    private func binding(for pluginID: String) -> Binding<Bool> {
        Binding(
            get: { enabledPlugins[pluginID] ?? true },
            set: { newValue in
                enabledPlugins[pluginID] = newValue
                dataSource.setPluginEnabled(pluginID, enabled: newValue)
            }
        )
    }
}

/// 某个插件自己的功能选项。快捷键不在这里
private struct PluginOptionsPane: View {
    let plugin: SettingsPlugin
    let dataSource: any SettingsDataSource

    var body: some View {
        if plugin.id == LauncherPluginID.launcher {
            ApplicationsSettingsPane(dataSource: dataSource)
            CommandsSettingsPane(dataSource: dataSource)
        } else if plugin.id == LauncherPluginID.systemControl {
            SystemActionsSettingsPane(dataSource: dataSource)
        } else if let tab = SettingsTab.allCases.first(where: { $0.pluginID == plugin.id }) {
            FeatureSettingsPane(tab: tab, dataSource: dataSource)
        }
    }
}

/// 避免 QuickUI 依赖插件包，只用插件 id 字面量
private enum LauncherPluginID {
    static let launcher = "launcher"
    static let systemControl = "systemcontrol"
}
