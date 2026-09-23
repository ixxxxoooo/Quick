// AISettingsPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 宿主级 AI 服务设置
///
/// 一份配置、所有插件共用：翻译、摘要、改写这类能力都通过 `AIService` 读这里，
/// 不需要各自填 Key。参考业界做法，字段是「服务商 / API Key / Base URL / 模型 /
/// 生成参数 / 连接测试」。
public struct AISettingsPane: View {

    let dataSource: any SettingsDataSource

    @AppStorage(SettingsKey.AI.enabled) private var enabled = false
    @AppStorage(SettingsKey.AI.provider) private var providerRaw = AIProviderKind.deepseek.rawValue
    @AppStorage(SettingsKey.AI.baseURL) private var baseURL = ""
    @AppStorage(SettingsKey.AI.model) private var model = ""
    @AppStorage(SettingsKey.AI.maxTokens) private var maxTokens = AIConfig.defaultMaxTokens
    @AppStorage(SettingsKey.AI.temperature) private var temperature = AIConfig.defaultTemperature

    /// API Key 只走 Keychain，不用 @AppStorage
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var isTesting = false
    @State private var testResult: SettingsAITestResult?

    private var provider: AIProviderKind {
        AIProviderKind(rawValue: providerRaw) ?? .deepseek
    }

    public init(dataSource: any SettingsDataSource) {
        self.dataSource = dataSource
    }

    public var body: some View {
        Form {
            overviewSection
            providerSection
            advancedSection
        }
        .formStyle(.grouped)
        .onAppear {
            apiKey = AIConfig.load().apiKey
        }
        .onChange(of: apiKey) { _, newValue in
            persistAPIKey(newValue)
        }
        .onChange(of: providerRaw) { _, _ in
            // 换服务商就把覆盖值清空，回到新服务商的默认 Base URL / 模型
            baseURL = ""
            model = ""
            testResult = nil
        }
    }

    // MARK: - 总览

    private var overviewSection: some View {
        Section {
            Toggle(isOn: $enabled) {
                SettingsRow(
                    title: "启用 AI 能力",
                    subtitle: "开启后，翻译、摘要等插件可以调用这里配置的模型。",
                    icon: { SettingsRowIcon(systemImage: "brain") }
                )
            }
        } header: {
            Text("总览")
        } footer: {
            Text("AI 由宿主统一配置，插件通过这套基座访问 —— 换服务商、换 Key 只改一处。")
        }
    }

    // MARK: - 服务商

    private var providerSection: some View {
        Section {
            Picker(selection: $providerRaw) {
                ForEach(AIProviderKind.allCases) { kind in
                    Text(kind.title).tag(kind.rawValue)
                }
            } label: {
                SettingsRow(
                    title: "服务商",
                    subtitle: "切换服务商会重置下面两项的默认值。",
                    icon: { SettingsRowIcon(systemImage: "server.rack") }
                )
            }

            SettingsRow(
                title: "API Key",
                subtitle: provider.requiresAPIKey
                    ? "只存在本机 Keychain，不会进偏好 plist，也不会上传。"
                    : "本地 Ollama 无需填写。",
                icon: { SettingsRowIcon(systemImage: "key") }
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Group {
                        if showKey {
                            TextField("sk-…", text: $apiKey)
                        } else {
                            SecureField("sk-…", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .font(DesignTokens.Typography.compactIcon)
                    }
                    .buttonStyle(.borderless)
                    .help(showKey ? "隐藏" : "显示")
                }
            }

            SettingsRow(
                title: "Base URL",
                subtitle: defaultDescription(provider.defaultBaseURL, emptyHint: "自定义服务商需填写"),
                icon: { SettingsRowIcon(systemImage: "link") }
            ) {
                TextField(provider.defaultBaseURL, text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }

            SettingsRow(
                title: "模型",
                subtitle: defaultDescription(provider.defaultModel, emptyHint: "自定义服务商需填写"),
                icon: { SettingsRowIcon(systemImage: "cpu") }
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    TextField(provider.defaultModel, text: $model)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

                    if !provider.suggestedModels.isEmpty {
                        Menu {
                            ForEach(provider.suggestedModels, id: \.self) { name in
                                Button(name) { model = name }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(DesignTokens.Typography.compactIcon)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24)
                        .help("选择常见模型")
                    }
                }
            }

            SettingsRow(
                title: "连接测试",
                subtitle: testResult?.message ?? "填好配置后点一下，确认能通。",
                icon: { SettingsRowIcon(systemImage: "bolt.horizontal") }
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button("测试") { runTest() }
                        .disabled(isTesting)
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else if let result = testResult {
                        Image(
                            systemName: result.isSuccess
                                ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .foregroundStyle(
                            result.isSuccess ? DesignTokens.Colors.success : DesignTokens.Colors.destructive
                        )
                    }
                }
            }
        } header: {
            Text("服务商与密钥")
        } footer: {
            Text("除 Anthropic 外都走 OpenAI 兼容协议（`/chat/completions`）；Anthropic 走 `/messages`。")
        }
    }

    // MARK: - 生成参数

    private var advancedSection: some View {
        Section {
            SettingsRow(
                title: "最大生成长度",
                subtitle: "单次回复最多多少 token。",
                icon: { SettingsRowIcon(systemImage: "text.badge.plus") }
            ) {
                Stepper(
                    "\(maxTokens)",
                    value: $maxTokens,
                    in: AIConfig.minMaxTokens...AIConfig.maxMaxTokens,
                    step: 256
                )
                .frame(width: 140)
            }

            SettingsRow(
                title: "采样温度",
                subtitle: "越低越稳定，越高越发散（0–2）。",
                icon: { SettingsRowIcon(systemImage: "thermometer.medium") }
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Slider(value: $temperature, in: 0...2, step: 0.1)
                        .frame(width: 160)
                    Text(String(format: "%.1f", temperature))
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        } header: {
            Text("生成参数")
        }
    }

    // MARK: - 行为

    private func defaultDescription(_ value: String, emptyHint: String) -> String {
        value.isEmpty ? emptyHint : "留空使用默认：\(value)"
    }

    private func persistAPIKey(_ key: String) {
        do {
            try AIConfig.saveAPIKey(key)
        } catch {
            QuickLog.persistence.error(
                "写入 API Key 到 Keychain 失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    private func runTest() {
        isTesting = true
        testResult = nil
        Task {
            let result = await dataSource.testAIConnection()
            isTesting = false
            testResult = result
        }
    }
}
