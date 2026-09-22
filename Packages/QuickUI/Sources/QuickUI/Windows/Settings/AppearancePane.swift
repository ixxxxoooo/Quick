// AppearancePane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 外观设置面板
///
/// 参考 Tinycast 项目：
/// - 主题模式（跟随系统、浅色、深色）
/// - 面板尺寸与缩放档位（1.0x 基础 / 1.1x 标准 / 1.2x 宽松）
/// - 屏幕位置（鼠标所在屏幕 / 主显示器）
/// - 菜单栏图标开关
/// - 毛玻璃背景与透明度
/// - 界面细节（行图标、底栏按键提示）
struct AppearancePane: View {

    let dataSource: any SettingsDataSource

    @AppStorage(SettingsKey.appearance)
    private var appearance = AppAppearance.system.rawValue

    @AppStorage(SettingsKey.paletteScale)
    private var paletteScale: Double = 1.1

    @AppStorage(SettingsKey.paletteScreen)
    private var paletteScreen = "cursor"

    @AppStorage(SettingsKey.showInMenuBar)
    private var showInMenuBar = true

    @AppStorage(SettingsKey.panelTransparency)
    private var panelTransparency = 0

    @AppStorage(SettingsKey.showResultIcons)
    private var showResultIcons = true

    @AppStorage(SettingsKey.showBottomBarHints)
    private var showBottomBarHints = true

    var body: some View {
        Form {
            themeSection
            sizeSection
            placementSection
            menuBarSection
            transparencySection
            detailsSection
        }
        .formStyle(.grouped)
    }

    /// 主题
    private var themeSection: some View {
        Section {
            Picker(selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            } label: {
                SettingsRow(
                    title: "主题风格",
                    subtitle: "跟随系统，或把 Quick 固定在浅色 / 深色模式。",
                    icon: { SettingsRowIcon(systemImage: "circle.lefthalf.filled") }
                )
            }
        } header: {
            Text("主题")
        } footer: {
            Text("面板、设置窗口与分离窗口即时生效，无需重启应用。")
        }
    }

    /// 面板尺寸缩放
    private var sizeSection: some View {
        Section {
            Picker(selection: $paletteScale) {
                Text("基础 (1.0x — 750 × 475)").tag(1.0)
                Text("标准 (1.1x — 825 × 523)").tag(1.1)
                Text("宽松 (1.2x — 900 × 570)").tag(1.2)
            } label: {
                SettingsRow(
                    title: "面板尺寸",
                    subtitle: "参考 Tinycast 调色板的三档缩放比例。",
                    icon: { SettingsRowIcon(systemImage: "arrow.up.left.and.arrow.down.right") }
                )
            }
        } header: {
            Text("尺寸与几何")
        } footer: {
            Text("缩放同时影响主面板、HUD 与模态对话框，设置窗口等系统窗口保持标准尺寸。")
        }
    }

    /// 呼出位置
    private var placementSection: some View {
        Section {
            Picker(selection: $paletteScreen) {
                Text("鼠标指针所在屏幕").tag("cursor")
                Text("主显示器 (Primary)").tag("main")
            } label: {
                SettingsRow(
                    title: "唤出屏幕",
                    subtitle: "多显示器环境下快捷键唤出面板的所在屏幕。",
                    icon: { SettingsRowIcon(systemImage: "display") }
                )
            }
        } header: {
            Text("显示屏幕")
        }
    }

    /// 菜单栏常驻
    private var menuBarSection: some View {
        Section {
            Toggle(isOn: $showInMenuBar) {
                SettingsRow(
                    title: "显示菜单栏图标",
                    subtitle: "在 macOS 顶部菜单栏常驻 Quick 图标，方便快捷访问与唤醒。",
                    icon: { SettingsRowIcon(systemImage: "menubar.rectangle") }
                )
            }
        } header: {
            Text("菜单栏")
        }
    }

    /// 毛玻璃与透明度
    private var transparencySection: some View {
        Section {
            SettingsRow(
                title: "面板背景不透明度",
                subtitle: "调节毛玻璃底层遮罩浓度，数值越高背景越实。",
                icon: { SettingsRowIcon(systemImage: "slider.horizontal.below.rectangle") }
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Slider(
                        value: Binding(
                            get: { Double(panelTransparency) },
                            set: { panelTransparency = Int($0) }
                        ),
                        in: -50...50,
                        step: 5
                    )
                    .frame(width: 120)

                    Text("\(panelTransparency > 0 ? "+\(panelTransparency)" : "\(panelTransparency)")%")
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        } header: {
            Text("材质与视觉")
        }
    }

    /// 界面细节
    private var detailsSection: some View {
        Section {
            Toggle(isOn: $showResultIcons) {
                SettingsRow(
                    title: "显示结果图标",
                    subtitle: "在搜索列表每一行左侧展示对应的应用或插件图标。",
                    icon: { SettingsRowIcon(systemImage: "app") }
                )
            }

            Toggle(isOn: $showBottomBarHints) {
                SettingsRow(
                    title: "显示底栏按键提示",
                    subtitle: "在面板底部浮动栏右侧显示操作提示（如打开 ↵、分离 ⌘D）。",
                    icon: { SettingsRowIcon(systemImage: "command") }
                )
            }
        } header: {
            Text("界面元素")
        }
    }
}
