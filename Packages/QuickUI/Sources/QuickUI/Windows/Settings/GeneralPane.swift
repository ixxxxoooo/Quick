// GeneralPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 通用设置
struct GeneralPane: View {

    let dataSource: any SettingsDataSource

    @State private var launchAtLogin: Bool
    @AppStorage(SettingsKey.paletteAutoPasteSeconds)
    private var autoPasteSeconds = PaletteAutoBehavior.defaultPasteWindow.rawValue
    @AppStorage(SettingsKey.paletteAutoClearMinutes)
    private var autoClearMinutes = PaletteAutoBehavior.defaultClearIdle.rawValue
    @AppStorage(SettingsKey.appearance)
    private var appearance = AppAppearance.system.rawValue

    init(dataSource: any SettingsDataSource) {
        self.dataSource = dataSource
        _launchAtLogin = State(initialValue: dataSource.isLaunchAtLoginEnabled)
    }

    var body: some View {
        Form {
            Section("启动") {
                Toggle(isOn: $launchAtLogin) {
                    SettingsRow(
                        title: "开机自动启动",
                        subtitle: "登录后在菜单栏常驻，不打开任何窗口。",
                        icon: { SettingsRowIcon(systemImage: "power") }
                    )
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    dataSource.setLaunchAtLogin(newValue)
                }
            }

            Section("唤出") {
                SettingsRow(
                    title: "全局快捷键",
                    subtitle: "在任何应用里按下即可唤出/隐藏面板。",
                    icon: { SettingsRowIcon(systemImage: "keyboard") }
                ) {
                    ShortcutRecorder(
                        keycaps: dataSource.globalShortcutKeycaps,
                        onRecord: { keyCode, modifiers in
                            dataSource.setGlobalShortcut(keyCode: keyCode, carbonModifiers: modifiers)
                        },
                        onClear: {
                            dataSource.clearGlobalShortcut()
                        }
                    )
                }

                SettingsRow(
                    title: "关闭面板",
                    subtitle: "按 Esc，或点击面板以外的任意位置。",
                    icon: { SettingsRowIcon(systemImage: "escape") }
                ) {
                    KeyCapChip(text: "Esc", style: .outline)
                }
            }

            Section {
                Picker(selection: $autoPasteSeconds) {
                    ForEach(PaletteAutoBehavior.AutoPasteWindow.allCases) { window in
                        Text(window.title).tag(window.rawValue)
                    }
                } label: {
                    SettingsRow(
                        title: "自动粘贴搜索框",
                        subtitle: "刚复制过内容时，唤出面板自动把它填进搜索框。",
                        icon: { SettingsRowIcon(systemImage: "doc.on.clipboard") }
                    )
                }

                Picker(selection: $autoClearMinutes) {
                    ForEach(PaletteAutoBehavior.AutoClearIdle.allCases) { idle in
                        Text(idle.title).tag(idle.rawValue)
                    }
                } label: {
                    SettingsRow(
                        title: "自动清空搜索框",
                        subtitle: "搜索框内容放置超过这个时间后，下次打开面板时清空。",
                        icon: { SettingsRowIcon(systemImage: "eraser") }
                    )
                }
            } header: {
                Text("面板行为")
            } footer: {
                Text("两项都只在打开面板的那一刻生效，不会打断你正在进行的输入。")
            }

            keyboardLayoutSection

            appearanceSection
        }
        .formStyle(.grouped)
    }

    /// 外观
    ///
    /// 只写偏好，真正的应用在 `AppCore.applyAppearance()` —— `NSApp.appearance` 是应用级
    /// 的，由那里一处负责，面板、设置窗口、分离窗口才不会各说各话。
    private var appearanceSection: some View {
        Section {
            Picker(selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            } label: {
                SettingsRow(
                    title: "主题",
                    subtitle: "跟随系统，或把 Quick 固定在浅色 / 深色。",
                    icon: { SettingsRowIcon(systemImage: "circle.lefthalf.filled") }
                )
            }
        } header: {
            Text("外观")
        } footer: {
            Text("面板、设置窗口与分离窗口一起生效，不必重启。")
        }
    }

    /// 强制键盘布局
    ///
    /// 中文输入法用户在拼音状态下按 ⌥Space，打出来的是拼音串 —— 切到 ABC 才能直接输命令。
    /// 面板关闭时会还原原来的布局。
    private var keyboardLayoutSection: some View {
        Section {
            Picker(selection: forcedLayoutBinding) {
                Text("不切换").tag("")
                ForEach(dataSource.keyboardLayouts) { layout in
                    Text(layout.name).tag(layout.id)
                }
            } label: {
                SettingsRow(
                    title: "强制键盘布局",
                    subtitle: "面板打开期间切换到指定键盘布局，关闭后还原。留空则不切换。",
                    icon: { SettingsRowIcon(systemImage: "keyboard.badge.ellipsis") }
                )
            }
        } header: {
            Text("输入法")
        } footer: {
            Text("列表来自系统已启用的键盘布局；在「系统设置 → 键盘 → 输入法」里增删。")
        }
    }

    /// 强制布局的绑定（空串代表不切换）
    private var forcedLayoutBinding: Binding<String> {
        Binding(
            get: { dataSource.forcedKeyboardLayoutID ?? "" },
            set: { dataSource.setForcedKeyboardLayout($0.isEmpty ? nil : $0) }
        )
    }
}
