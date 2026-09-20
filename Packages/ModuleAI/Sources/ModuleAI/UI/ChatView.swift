// ChatView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// AI 设置视图
///
/// 管理各 Provider 的启用状态和窗口偏好。
struct AISettingsView: View {
    @AppStorage("ai.defaultAlwaysOnTop") private var alwaysOnTop = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $alwaysOnTop) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("窗口默认置顶")
                        Text("新打开的 AI 窗口默认悬浮在最前")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        self._isEnabled = AppStorage(wrappedValue: true, "ai.provider.\(provider.id).enabled")
    }

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: provider.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: provider.accent) ?? Color.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.system(size: 13, weight: .medium))
                    Text(provider.url.replacingOccurrences(of: "https://", with: ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
