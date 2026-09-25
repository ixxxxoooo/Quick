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
                Text(
                    "每个 AI 服务在独立窗口中运行，关闭窗口后登录态保持。"
                    + "触发词就是服务自己的名称（下面列出的别名同样可用），"
                    + "在主面板搜索或到「快捷键」页输入它即可直达。"
                )
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Toggle(isOn: $isEnabled) {
                HStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: provider.icon)
                        .font(DesignTokens.Typography.iconGlyph)
                        .foregroundStyle(Color(hex: provider.accent) ?? Color.accentColor)
                        .frame(width: DesignTokens.Size.rowIcon)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name)
                            .font(DesignTokens.Typography.rowTitle)
                        Text(provider.url.replacingOccurrences(of: "https://", with: ""))
                            .font(DesignTokens.Typography.compactKeyCap)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
            }

            // 触发词是只读的：它就是服务名，用户没有要配的东西 ——
            // 列出来只是让人知道打什么能搜到，别做成一个长得像输入框的摆设
            Text("触发词：\(provider.triggerWords.joined(separator: "、"))")
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        // 命令表要跟着开关走：停用的 Provider 不该还能在「快捷键」页解出关键字、
        // 也不该在主面板搜到 —— 那时按下去什么都不会发生。宿主收到事件后重建命令快照。
        .onChange(of: isEnabled) { _, _ in
            EventBus.shared.post(CommandCatalogChangedEvent())
        }
    }
}
