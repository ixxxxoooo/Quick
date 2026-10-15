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

    let dataSource: any LauncherSettingsDataSource & CommandSettingsDataSource & PluginSettingsDataSource

    @AppStorage(PluginSettingKey.SystemControl.confirmDestructive) private var confirmDestructive = true

    var body: some View {
        let actions = dataSource.systemActions
        return Form {
            PluginIntroSection(dataSource: dataSource, pluginID: "systemcontrol")
            Section {
                Toggle(isOn: $confirmDestructive) {
                    SettingsRow(
                        title: "危险操作前确认",
                        subtitle: "重新启动、关机、退出登录、清空废纸篓执行前先弹出确认框；热键触发时同样生效。",
                        icon: { SettingsRowIcon(systemImage: "exclamationmark.triangle") }
                    )
                }
            }
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
    let dataSource: any LauncherSettingsDataSource & CommandSettingsDataSource & PluginSettingsDataSource

    @State private var alias: String
    @State private var isEnabled: Bool

    init(action: SettingsSystemActionItem, dataSource: any LauncherSettingsDataSource & CommandSettingsDataSource & PluginSettingsDataSource) {
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
                .frame(width: DesignTokens.Size.settingsRowIcon, height: DesignTokens.Size.settingsRowIcon)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(action.title)
                    .lineLimit(1)
                Text(action.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            AliasField(
                placeholder: "添加别名",
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
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }
}
