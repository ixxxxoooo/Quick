// SystemActionsSettingsPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 系统操作设置面板
///
/// 参考 Tinycast 设计：
/// - 列出系统操作命令（锁定屏幕、睡眠、重启、关机、清空废纸篓、推出磁盘、深色模式等）
/// - 支持筛选命令
/// - 每项可配置别名，以及是否出现在主搜索里。快捷键在「快捷键」页绑定
struct SystemActionsSettingsPane: View {

    let dataSource: any SettingsDataSource

    var body: some View {
        let actions = dataSource.systemActions
        return Form {
            PluginIntroSection(dataSource: dataSource, pluginID: "systemcontrol")
            Section {
                if actions.isEmpty {
                    Text("暂无系统操作")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, DesignTokens.Spacing.md)
                } else {
                    ForEach(actions) { action in
                        SystemActionRow(action: action, dataSource: dataSource)
                    }
                }
            } header: {
                Text("系统控制操作 (\(actions.count))")
            } footer: {
                Text("关掉的命令不会出现在主搜索里，已绑定的快捷键也不会生效。快捷键在「快捷键」页设置。")
            }
        }
        .formStyle(.grouped)
    }
}

private struct SystemActionRow: View {
    let action: SettingsSystemActionItem
    let dataSource: any SettingsDataSource

    @State private var alias: String
    @State private var isEnabled: Bool

    init(action: SettingsSystemActionItem, dataSource: any SettingsDataSource) {
        self.action = action
        self.dataSource = dataSource
        _alias = State(initialValue: action.alias ?? "")
        _isEnabled = State(initialValue: action.isEnabled)
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: action.icon)
                .font(DesignTokens.Typography.iconGlyph)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .lineLimit(1)
                Text(action.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            AliasField(
                placeholder: "Add Alias",
                text: $alias,
                onChange: { newValue in
                    dataSource.setSystemActionAlias(newValue, for: action.id)
                }
            )

            Toggle(isOn: $isEnabled) {
                Text("打开")
            }
            .toggleStyle(.checkbox)
            .onChange(of: isEnabled) { _, newValue in
                dataSource.setCommandEnabled(CommandID.systemAction(action.id), enabled: newValue)
            }
        }
        .padding(.vertical, 2)
    }
}
