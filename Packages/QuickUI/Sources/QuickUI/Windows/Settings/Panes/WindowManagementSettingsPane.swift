// WindowManagementSettingsPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 窗口管理设置面板
struct WindowManagementSettingsPane: View {

    let dataSource: any SettingsDataSource

    @AppStorage(PluginSettingKey.WindowManager.enabled) private var isEnabled = false
    @AppStorage(PluginSettingKey.WindowManager.showInLauncher) private var showInLauncher = true
    @AppStorage(PluginSettingKey.WindowManager.cycling) private var cycling = "None"
    @AppStorage(PluginSettingKey.WindowManager.gap) private var gap = 0
    @AppStorage(PluginSettingKey.WindowManager.showLayoutsInLauncher) private var showLayoutsInLauncher = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $isEnabled) {
                    SettingsRow(
                        title: "启用窗口管理",
                        subtitle: "允许 Quick 通过辅助功能权限移动和调整其他应用的窗口大小。",
                        icon: { SettingsRowIcon(systemImage: "macwindow") }
                    )
                }
                Toggle(isOn: $showInLauncher) {
                    SettingsRow(
                        title: "在启动器中显示",
                        subtitle: "搜索时展示窗口管理命令。"
                    )
                }
                .settingsEnabled(isEnabled)
            }

            Group {
                optionsSection
                windowLayoutsSection
                layoutCommandsSection
            }
            .settingsEnabled(isEnabled)
        }
        .formStyle(.grouped)
    }

    private var optionsSection: some View {
        Section {
            Picker(selection: $cycling) {
                Text("无").tag("None")
                Text("半屏和三分之一").tag("Halves and Thirds")
                Text("跨显示器").tag("Across Displays")
            } label: {
                SettingsRow(
                    title: "循环切换",
                    subtitle: cycleDetail(for: cycling),
                    icon: { SettingsRowIcon(systemImage: "arrow.triangle.2.circlepath") }
                )
            }

            SettingsRow(
                title: "窗口间距",
                subtitle: "平铺窗口之间以及屏幕边缘留白的像素值。",
                icon: { SettingsRowIcon(systemImage: "rectangle.split.2x1") }
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("\(gap) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("窗口间距", value: $gap, in: 0...64, step: 2)
                        .labelsHidden()
                }
            }
        } header: {
            Text("选项")
        }
    }

    private func cycleDetail(for cycling: String) -> String {
        switch cycling {
        case "Halves and Thirds":
            return "重复触发半屏布局时，依次切换为三分之一和三分之二。"
        case "Across Displays":
            return "重复触发半屏布局时，依次移动到下一个显示器的对应位置。"
        default:
            return "重复触发相同布局时保持不变。"
        }
    }

    private var windowLayoutsSection: some View {
        Section {
            Toggle(isOn: $showLayoutsInLauncher) {
                SettingsRow(
                    title: "在启动器中显示布局",
                    subtitle: "搜索时展示你保存的窗口布局。"
                )
            }

            Text("保存一次窗口排列，之后用一个快捷键即可恢复全部窗口位置。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("新建布局") {
                // 新建布局
            }

            Button("从当前窗口创建布局") {
                // 根据当前窗口创建布局
            }
        } header: {
            Text("窗口布局")
        } footer: {
            Text("布局会记住指定应用在指定显示器上的大小和位置，一键还原。")
        }
    }

    private var layoutCommandsSection: some View {
        Section {
            ForEach(WindowLayoutItem.defaults) { item in
                WindowCommandRow(item: item)
            }
        } header: {
            Text("布局命令")
        }
    }
}

private struct WindowLayoutItem: Identifiable {
    let id: String
    let name: String
    let icon: String

    static let defaults: [WindowLayoutItem] = [
        WindowLayoutItem(id: "leftHalf", name: "左半屏", icon: "rectangle.lefthalf.filled"),
        WindowLayoutItem(id: "rightHalf", name: "右半屏", icon: "rectangle.righthalf.filled"),
        WindowLayoutItem(id: "topHalf", name: "上半屏", icon: "rectangle.tophalf.filled"),
        WindowLayoutItem(id: "bottomHalf", name: "下半屏", icon: "rectangle.bottomhalf.filled"),
        WindowLayoutItem(id: "maximize", name: "最大化", icon: "arrow.up.left.and.arrow.down.right"),
        WindowLayoutItem(id: "center", name: "居中", icon: "rectangle.center.inset.filled"),
        WindowLayoutItem(id: "topLeft", name: "左上角", icon: "rectangle.inset.topleading.filled"),
        WindowLayoutItem(id: "topRight", name: "右上角", icon: "rectangle.inset.toptrailing.filled"),
        WindowLayoutItem(id: "bottomLeft", name: "左下角", icon: "rectangle.inset.bottomleading.filled"),
        WindowLayoutItem(
            id: "bottomRight", name: "右下角", icon: "rectangle.inset.bottomtrailing.filled")
    ]
}

private struct WindowCommandRow: View {
    let item: WindowLayoutItem

    @AppStorage private var isVisible: Bool
    @State private var alias: String = ""

    init(item: WindowLayoutItem) {
        self.item = item
        _isVisible = AppStorage(wrappedValue: true, "windowManager.cmd.\(item.id).visible")
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

            AliasField(
                placeholder: "设置别名",
                text: $alias
            )

            ShortcutRecorder(
                keycaps: nil,
                onRecord: { _, _ in },
                onClear: {}
            )

            Toggle("", isOn: $isVisible)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("在启动器中显示")
                .accessibilityLabel("显示 \(item.name)")
        }
        .padding(.vertical, 2)
    }
}
