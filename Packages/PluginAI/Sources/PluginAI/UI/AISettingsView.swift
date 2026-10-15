// AISettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// AI 设置视图
///
/// 窗口行为和 Provider 开关合并在一个平面列表里，不做二级分组。
struct AISettingsView: View {
    @AppStorage(PluginSettingKey.AIPortal.defaultAlwaysOnTop) private var alwaysOnTop = false
    @AppStorage(PluginSettingKey.AIPortal.mergeWindows) private var mergeWindows = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $mergeWindows) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text("合并为标签页窗口")
                        Text("开启后所有 AI 服务共用一个窗口，通过标签页切换")
                            .font(DesignTokens.Typography.keyCap)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
                .help("关闭时每个 AI 服务使用独立窗口")

                Toggle(isOn: $alwaysOnTop) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text("窗口默认置顶")
                        Text("新打开的 AI 窗口默认悬浮在最前")
                            .font(DesignTokens.Typography.keyCap)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
                .help("窗口置顶后不会被其他窗口遮挡")
            } header: {
                Text("窗口行为")
            }

            Section {
                ForEach(AIProviderRegistry.all) { provider in
                    AIProviderSettingsRow(provider: provider)
                }
            } header: {
                Text("AI 服务")
            } footer: {
                Text("每个 AI 服务保持独立登录态。触发词就是服务名称，在主面板搜索即可直达。想用 API Key 在主面板按 Tab 对话，请到「设置 › AI 服务」。")
            }
        }
        .formStyle(.grouped)
        .onChange(of: mergeWindows) { _, _ in
            // 模式切换时通知插件重建窗口
            EventBus.shared.post(CommandCatalogChangedEvent())
        }
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
                    .frame(width: DesignTokens.Size.rowIcon)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(provider.name)
                        .font(DesignTokens.Typography.rowTitle)
                    Text(provider.url.replacingOccurrences(of: "https://", with: ""))
                        .font(DesignTokens.Typography.compactKeyCap)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
        }
        .onChange(of: isEnabled) { _, _ in
            EventBus.shared.post(CommandCatalogChangedEvent())
        }
    }
}
