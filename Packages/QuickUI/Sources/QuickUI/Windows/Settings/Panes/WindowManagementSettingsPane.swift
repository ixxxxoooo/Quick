// WindowManagementSettingsPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 窗口管理设置面板
///
/// 只放**真的生效**的选项。这个面板以前是一份原型：里面有与插件真实启用状态冲突的
/// 第二个「启用」开关、没有实现支撑的循环切换与窗口间距、函数体为空的「新建布局」
/// 按钮，以及绑在从不落盘的局部状态上的别名框和回调为空的快捷键录制器。
/// 能拨动却什么也不做的控件比没有这个控件更糟 —— 用户会以为功能坏了。
///
/// 尚未实现的部分（保存布局、循环切换、窗口间距、逐命令快捷键与别名）等真正做出来
/// 再连控件一起加回来。
struct WindowManagementSettingsPane: View {

    let dataSource: any SettingsDataSource

    @AppStorage(PluginSettingKey.WindowManager.showInLauncher) private var showInLauncher = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $showInLauncher) {
                    SettingsRow(
                        title: "在启动器中显示",
                        subtitle: "搜索时展示窗口管理命令。关闭后这个插件不再出现在搜索结果里。",
                        icon: { SettingsRowIcon(systemImage: "macwindow") }
                    )
                }
            } header: {
                Text("显示")
            } footer: {
                Text("插件本身的启停在上方「窗口管理」那一栏里，这里只管搜索结果的显隐。")
            }

            layoutCommandsSection

            Section {
                SettingsRow(
                    title: "移动窗口需要辅助功能权限",
                    subtitle: "首次使用时会请求。系统设置 → 隐私与安全性 → 辅助功能。",
                    icon: { SettingsRowIcon(systemImage: "lock.shield") }
                )
            } header: {
                Text("权限")
            }
        }
        .formStyle(.grouped)
    }

    /// 逐条布局命令的显隐
    private var layoutCommandsSection: some View {
        Section {
            ForEach(dataSource.windowLayoutCommands) { item in
                WindowCommandRow(item: item)
            }
        } header: {
            Text("布局命令")
        } footer: {
            Text("关掉的命令不会出现在搜索结果里，快捷键绑定也一并失效。")
        }
    }
}

/// 单条布局命令：一个显隐复选框
private struct WindowCommandRow: View {
    let item: SettingsWindowLayoutCommand

    @AppStorage private var isVisible: Bool

    init(item: SettingsWindowLayoutCommand) {
        self.item = item
        _isVisible = AppStorage(
            wrappedValue: true,
            PluginSettingKey.WindowManager.commandVisible(item.id))
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: item.icon)
                .font(DesignTokens.Typography.iconGlyph)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)

            Text(item.name)
                .lineLimit(1)

            Spacer(minLength: DesignTokens.Spacing.md)

            Toggle("", isOn: $isVisible)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("在启动器中显示")
                .accessibilityLabel("显示 \(item.name)")
        }
        .padding(.vertical, 2)
    }
}
