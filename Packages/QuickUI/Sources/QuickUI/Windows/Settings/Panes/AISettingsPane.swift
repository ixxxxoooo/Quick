// AISettingsPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickPlatform
import SwiftUI

/// 宿主级 AI 服务设置
///
/// 一份配置、所有 AI 能力共用（主面板里 Tab 进入的 AI 对话等）。
/// 可以添加多个服务商：常见的一键预设，其余自定义名称与地址；
/// 每个服务商各自维护 Key 与模型列表，模型可手动输入、从常见模型选或自动拉取后勾选。
public struct AISettingsPane: View {

    @AppStorage(SettingsKey.AI.maxTokens) private var maxTokens = AIConfig.defaultMaxTokens
    @AppStorage(SettingsKey.AI.temperature) private var temperature = AIConfig.defaultTemperature

    @State private var providers: [AIProvider] = []
    @State private var keyedProviderIDs: Set<String> = []
    @State private var defaultModel: AIModelRef?
    @State private var editing: EditingTarget?
    @State private var confirmClearHistory = false

    /// 正在编辑的服务商；新建时 `isNew` 为真，保存才真正加入列表
    private struct EditingTarget: Identifiable {
        let provider: AIProvider
        let isNew: Bool
        var id: String { provider.id }
    }

    public init() {}

    private var choices: [AIModelChoice] {
        AIProviderStore.choices(providers: providers) { keyedProviderIDs.contains($0.id) }
    }

    public var body: some View {
        Form {
            providersSection
            defaultModelSection
            generationSection
            historySection
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .sheet(item: $editing) { target in
            AIProviderEditorSheet(
                provider: target.provider,
                isNew: target.isNew,
                onSave: { save($0) },
                onDelete: { delete(target.provider) }
            )
        }
        .confirmationDialog(
            "清除全部 AI 对话历史？", isPresented: $confirmClearHistory, titleVisibility: .visible
        ) {
            Button("清除", role: .destructive, action: clearHistory)
        } message: {
            Text("所有会话与消息都会被删除，无法恢复。")
        }
    }

    // MARK: - 服务商

    private var providersSection: some View {
        Section {
            ForEach(providers) { provider in
                providerRow(provider)
            }

            Menu {
                Section("常见服务商") {
                    ForEach(AIProviderPresets.all) { preset in
                        Button {
                            editing = EditingTarget(provider: AIProvider(preset: preset), isNew: true)
                        } label: {
                            Label(preset.name, systemImage: preset.symbol)
                        }
                    }
                }
                Divider()
                Button {
                    editing = EditingTarget(provider: .custom(), isNew: true)
                } label: {
                    Label("自定义服务商…", systemImage: "plus.square.dashed")
                }
            } label: {
                Label("添加服务商", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } header: {
            Text("服务商")
        } footer: {
            Text(
                providers.isEmpty
                    ? "还没有服务商。添加一个，填上 API Key，就能在主面板按 Tab 与它对话。"
                    : "点一行编辑 Key 与模型。除 Anthropic 外都走 OpenAI 兼容协议。")
        }
    }

    private func providerRow(_ provider: AIProvider) -> some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Button {
                editing = EditingTarget(provider: provider, isNew: false)
            } label: {
                SettingsRow(
                    title: provider.displayName,
                    subtitle: summary(of: provider),
                    icon: {
                        SettingsRowIcon(
                            systemImage: provider.preset?.symbol ?? "server.rack",
                            isEnabled: provider.isEnabled)
                    }
                ) {
                    Image(systemName: "chevron.right")
                        .font(DesignTokens.Typography.compactIcon)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(
                "",
                isOn: Binding(
                    get: { provider.isEnabled },
                    set: { isOn in
                        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else {
                            return
                        }
                        providers[index].isEnabled = isOn
                        persist()
                    })
            )
            .labelsHidden()
            .accessibilityLabel("启用 \(provider.displayName)")
        }
    }

    /// 第二行：模型数 + Key 状态
    private func summary(of provider: AIProvider) -> String {
        let models = provider.models.isEmpty ? "未添加模型" : "\(provider.models.count) 个模型"
        let key: String
        if !provider.requiresAPIKey {
            key = "无需 Key"
        } else {
            key = keyedProviderIDs.contains(provider.id) ? "Key 已填" : "未填 Key"
        }
        return "\(models) · \(key)"
    }

    // MARK: - 默认模型

    private var defaultModelSection: some View {
        Section {
            let current = AIProviderStore.resolve(preferred: defaultModel, default: nil, choices: choices)
            Picker(
                selection: Binding(
                    get: { current?.ref },
                    set: { ref in
                        defaultModel = ref
                        AIProviderStore.setDefaultModel(ref)
                    })
            ) {
                if choices.isEmpty {
                    Text("暂无可用模型").tag(AIModelRef?.none)
                }
                ForEach(choices) { choice in
                    Text(choice.label).tag(Optional(choice.ref))
                }
            } label: {
                SettingsRow(
                    title: "默认模型",
                    subtitle: choices.isEmpty
                        ? "添加服务商、填好 Key 并至少添加一个模型后可选。"
                        : "新对话默认使用；对话里随时可以切换。",
                    icon: { SettingsRowIcon(systemImage: "cpu") }
                )
            }
            .disabled(choices.isEmpty)
        } header: {
            Text("对话")
        }
    }

    // MARK: - 生成参数

    private var generationSection: some View {
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
                .frame(width: DesignTokens.Size.settingsControlWide)
            }

            SettingsRow(
                title: "采样温度",
                subtitle: "越低越稳定，越高越发散（0–2）。Anthropic 上限为 1。",
                icon: { SettingsRowIcon(systemImage: "thermometer.medium") }
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Slider(value: $temperature, in: 0...AIConfig.maxTemperature, step: 0.1)
                        .frame(width: DesignTokens.Size.settingsFieldSmall)
                    Text(String(format: "%.1f", temperature))
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(.secondary)
                        .frame(width: DesignTokens.Size.settingsReadout, alignment: .trailing)
                }
            }
        } header: {
            Text("生成参数")
        }
    }

    // MARK: - 历史

    private var historySection: some View {
        Section {
            SettingsRow(
                title: "清除对话历史",
                subtitle: "删除 AI 对话里的全部会话。置顶的也会被删除。",
                icon: { SettingsRowIcon(systemImage: "trash") }
            ) {
                Button("清除…", role: .destructive) { confirmClearHistory = true }
            }
        } header: {
            Text("历史")
        }
    }

    // MARK: - 行为

    private func reload() {
        providers = AIProviderStore.loadProviders()
        keyedProviderIDs = Set(providers.filter { !AIProviderStore.apiKey(for: $0).isEmpty }.map(\.id))
        defaultModel = AIProviderStore.defaultModel()
    }

    private func persist() {
        AIProviderStore.saveProviders(providers)
    }

    private func save(_ provider: AIProvider) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
        persist()
        keyedProviderIDs =
            Set(providers.filter { !AIProviderStore.apiKey(for: $0).isEmpty }.map(\.id))
        // 第一个能用的模型自动成为默认，省得用户去二次选择
        let defaultStillValid = choices.contains { $0.ref == defaultModel }
        if !defaultStillValid, let first = choices.first {
            defaultModel = first.ref
            AIProviderStore.setDefaultModel(first.ref)
        }
        QuickLog.persistence.notice("AI 服务商已保存：\(provider.displayName, privacy: .private)")
    }

    private func delete(_ provider: AIProvider) {
        AIProviderStore.deleteAPIKey(for: provider)
        providers.removeAll { $0.id == provider.id }
        persist()
        keyedProviderIDs.remove(provider.id)
        if defaultModel?.providerID == provider.id {
            defaultModel = choices.first?.ref
            AIProviderStore.setDefaultModel(defaultModel)
        }
    }

    private func clearHistory() {
        ChatSessionFileStore().deleteAll()
        EventBus.shared.post(AIChatHistoryClearedEvent())
        QuickLog.persistence.notice("AI 对话历史已清除")
    }
}
