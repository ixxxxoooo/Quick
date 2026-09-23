// AISettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// AI 设置视图
///
/// 管理各 Provider 的启用状态和窗口偏好。
struct AISettingsView: View {
    @AppStorage(PluginSettingKey.AIPortal.defaultAlwaysOnTop) private var alwaysOnTop = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $alwaysOnTop) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("窗口默认置顶")
                        Text("新打开的 AI 窗口默认悬浮在最前")
                            .font(DesignTokens.Typography.keyCap)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
            } header: {
                Text("窗口偏好")
            }

            Section {
                ForEach(AIProviderRegistry.all) { provider in
                    AIProviderSettingsRow(provider: provider)
                }
            } header: {
                Text("AI 服务")
            } footer: {
                Text("每个 AI 服务在独立窗口中运行，关闭窗口后登录态保持。")
            }
        }
        .formStyle(.grouped)
    }
}

/// 单个 Provider 的设置行
private struct AIProviderSettingsRow: View {
    let provider: AIProvider
    @AppStorage private var isEnabled: Bool

    init(provider: AIProvider) {
        self.provider = provider
        self._isEnabled = AppStorage(
            wrappedValue: true, PluginSettingKey.AIPortal.providerEnabled(provider.id))
    }

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: provider.icon)
                    .font(DesignTokens.Typography.iconGlyph)
                    .foregroundStyle(Color(hex: provider.accent) ?? Color.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(DesignTokens.Typography.rowTitle)
                    Text(provider.url.replacingOccurrences(of: "https://", with: ""))
                        .font(DesignTokens.Typography.compactKeyCap)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
        }
    }
}
