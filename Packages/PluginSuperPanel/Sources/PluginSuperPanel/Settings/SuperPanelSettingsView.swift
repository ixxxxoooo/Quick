// SuperPanelSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import ApplicationServices
import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 超级面板设置页（含 Fasty 对齐的鼠标唤出选项）
struct SuperPanelSettingsView: View {

    @AppStorage(PluginSettingKey.SuperPanel.autoDetect) private var autoDetect = true
    @AppStorage(PluginSettingKey.SuperPanel.showGitActions) private var showGitActions = true
    @AppStorage(PluginSettingKey.SuperPanel.showBuildActions) private var showBuildActions = true
    @AppStorage(PluginSettingKey.SuperPanel.showFileNav) private var showFileNav = true
    @AppStorage(PluginSettingKey.SuperPanel.preferredTerminal) private var preferredTerminal = "Terminal"
    @AppStorage(PluginSettingKey.SuperPanel.showClipboard) private var showClipboard = true
    @AppStorage(PluginSettingKey.SuperPanel.showQuickTools) private var showQuickTools = true
    @AppStorage(PluginSettingKey.SuperPanel.mouseLongPressEnabled)
    private var mouseLongPressEnabled = SuperPanelMousePreferences.defaultLongPressEnabled
    @AppStorage(PluginSettingKey.SuperPanel.middleClickEnabled)
    private var middleClickEnabled = SuperPanelMousePreferences.defaultMiddleClickEnabled
    @AppStorage(PluginSettingKey.SuperPanel.mouseLongPressThresholdMs)
    private var mouseLongPressThresholdMs = SuperPanelMousePreferences.defaultThresholdMs

    @State private var accessibilityGranted = AXIsProcessTrusted()

    private let permissions = PermissionService()

    var body: some View {
        Form {
            Section {
                Toggle(
                    "长按鼠标右键触发",
                    isOn: $mouseLongPressEnabled
                )
                if mouseLongPressEnabled {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        HStack {
                            Text("长按判定时长")
                            Spacer()
                            Text("\(mouseLongPressThresholdMs) ms")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(mouseLongPressThresholdMs) },
                                set: {
                                    mouseLongPressThresholdMs =
                                        SuperPanelMousePreferences.clampedThreshold(Int($0))
                                }
                            ),
                            in: Double(
                                SuperPanelMousePreferences.minThresholdMs)...Double(
                                    SuperPanelMousePreferences.maxThresholdMs),
                            step: Double(SuperPanelMousePreferences.thresholdStepMs)
                        )
                        Text("右键按住达到此时长后弹出；中键为立即触发。")
                            .font(DesignTokens.Typography.rowTrailing)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(
                    "鼠标中键单击触发",
                    isOn: $middleClickEnabled
                )
            } header: {
                Text("唤醒与触发")
            } footer: {
                Text("在任意应用中唤出超级面板。中键会拦截事件以保留划词选中；长按触发后会拦截右键抬起，避免弹出系统菜单。")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text("辅助功能权限")
                        Text("鼠标监听与划词捕获需要辅助功能权限。")
                            .font(DesignTokens.Typography.rowTrailing)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if accessibilityGranted {
                        Label("已授权", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(DesignTokens.Colors.success)
                    } else {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Button("申请") {
                                permissions.requestAccessibility()
                                refreshAccessibility()
                            }
                            Button("打开系统设置") {
                                permissions.openAccessibilitySettings()
                            }
                            Button("重新检测") {
                                refreshAccessibility()
                            }
                        }
                    }
                }
            } header: {
                Text("权限")
            }

            Section("工作台") {
                Toggle("显示常用工具", isOn: $showQuickTools)
                Toggle("显示剪贴板预览", isOn: $showClipboard)
            }

            Section("项目检测") {
                Toggle("自动检测前台应用的项目", isOn: $autoDetect)

                Picker("首选终端", selection: $preferredTerminal) {
                    Text("Terminal").tag("Terminal")
                    Text("iTerm2").tag("iTerm2")
                    Text("Warp").tag("Warp")
                    Text("Kitty").tag("Kitty")
                    Text("Alacritty").tag("Alacritty")
                }
            }

            Section("项目操作") {
                Toggle("Git 操作", isOn: $showGitActions)
                Toggle("构建命令", isOn: $showBuildActions)
                Toggle("文件导航", isOn: $showFileNav)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshAccessibility)
    }

    private func refreshAccessibility() {
        accessibilityGranted = permissions.isAccessibilityGranted()
        // 授权后主动通知插件重试启动 CGEventTap（仅改权限不会触发 didChange）
        if accessibilityGranted {
            NotificationCenter.default.post(
                name: UserDefaults.didChangeNotification,
                object: UserDefaults.standard
            )
        }
    }
}
