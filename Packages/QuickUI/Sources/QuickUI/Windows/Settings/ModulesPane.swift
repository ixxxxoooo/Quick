// ModulesPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 插件开关
///
/// 插件数量较多时一屏放不下，所以顶部有一个筛选框（参考实现的做法：
/// 长列表上方给一个搜索框，而不是让用户自己滚）。
struct ModulesPane: View {

    let dataSource: any SettingsDataSource

    @State private var enabledModules: [String: Bool]
    @State private var filter = ""
    @FocusState private var filterFocused: Bool

    init(dataSource: any SettingsDataSource) {
        self.dataSource = dataSource
        _enabledModules = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: dataSource.moduleEntries.map {
                    ($0.id, dataSource.isModuleEnabled($0.id))
                }
            )
        )
    }

    /// 按筛选词过滤后的模块
    private var visibleModules: [SettingsModule] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return dataSource.moduleEntries }
        return dataSource.moduleEntries.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var disabledCount: Int {
        enabledModules.values.filter { !$0 }.count
    }

    var body: some View {
        Form {
            Section {
                SettingsFilterField(prompt: "筛选插件", query: $filter, isFocused: $filterFocused)
            }

            Section {
                if visibleModules.isEmpty {
                    SettingsRow(title: "没有匹配的插件", subtitle: "换个关键词试试")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleModules) { module in
                        Toggle(isOn: binding(for: module.id)) {
                            SettingsRow(
                                title: module.name,
                                // 副标题给日志分类名：排查「某个功能怎么没了」时，
                                // 这就是要在日志里 grep 的那个词。
                                subtitle: "module.\(module.id)",
                                icon: {
                                    SettingsRowIcon(
                                        systemImage: module.icon,
                                        isEnabled: enabledModules[module.id] ?? true
                                    )
                                }
                            )
                        }
                    }
                }
            } header: {
                Text("插件")
            } footer: {
                if disabledCount > 0 {
                    Text("已停用 \(disabledCount) 个插件。停用的插件不会被搜索到，也不会在启动时加载。")
                } else {
                    Text("停用的插件不会被搜索到，也不会在启动时加载。")
                }
            }
        }
        .formStyle(.grouped)
    }

    /// 单个模块的开关绑定
    ///
    /// 写回时同时更新本地状态与数据源：本地状态让开关立刻响应，
    /// 数据源负责持久化并同步模块实例。
    private func binding(for moduleID: String) -> Binding<Bool> {
        Binding(
            get: { enabledModules[moduleID] ?? true },
            set: { newValue in
                enabledModules[moduleID] = newValue
                dataSource.setModuleEnabled(moduleID, enabled: newValue)
            }
        )
    }
}
