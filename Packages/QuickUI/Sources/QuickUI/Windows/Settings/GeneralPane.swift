// GeneralPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 通用设置
struct GeneralPane: View {

    let dataSource: any SettingsDataSource

    @State private var launchAtLogin: Bool

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
        }
        .formStyle(.grouped)
    }
}
