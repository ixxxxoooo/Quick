// AIProviderEditorSheet.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickPlatform
import SwiftUI

/// 编辑一个 AI 服务商：名称、协议、地址、Key、模型列表、连接测试
///
/// 编辑的是副本（`draft`），点「保存」才写回；取消不留痕迹。
/// Key 单独走 Keychain，写入失败会留在弹窗里提示，而不是静默丢掉。
struct AIProviderEditorSheet: View {

    /// 新建还是编辑（决定标题与是否显示「删除」）
    let isNew: Bool
    let onSave: (AIProvider) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var draft: AIProvider
    @State private var apiKey: String
    @State private var showKey = false
    @State private var newModel = ""
    @State private var showModelPicker = false
    @State private var confirmDelete = false
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var saveError: String?

    init(
        provider: AIProvider, isNew: Bool,
        onSave: @escaping (AIProvider) -> Void, onDelete: @escaping () -> Void
    ) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: provider)
        _apiKey = State(initialValue: AIProviderStore.apiKey(for: provider))
    }

    private var isCustom: Bool { draft.presetID == nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                basicSection
                modelsSection
                testSection
                if !isNew { dangerSection }
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(width: DesignTokens.Size.aiEditorWidth, height: DesignTokens.Size.aiEditorHeight)
        .sheet(isPresented: $showModelPicker) {
            AIModelPickerSheet(
                endpoint: draft.endpoint(model: "", apiKey: apiKey),
                alreadyAdded: Set(draft.models)
            ) { picked in
                picked.forEach { draft.addModel($0) }
            }
        }
        .confirmationDialog(
            "删除「\(draft.displayName)」？", isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("它保存的 API Key 也会一并从 Keychain 清除。")
        }
    }

    // MARK: - 基本信息

    private var basicSection: some View {
        Section {
            SettingsRow(
                title: "名称",
                subtitle: isCustom ? "显示在模型选择里，随便起。" : nil,
                icon: { SettingsRowIcon(systemImage: draft.preset?.symbol ?? "server.rack") }
            ) {
                TextField("", text: $draft.name, prompt: Text("例如：公司网关"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(width: DesignTokens.Size.settingsFieldMedium)
            }

            if isCustom {
                SettingsRow(
                    title: "接口协议",
                    subtitle: "绝大多数服务商是 OpenAI 兼容；只有 Anthropic 官方接口例外。",
                    icon: { SettingsRowIcon(systemImage: "arrow.left.arrow.right") }
                ) {
                    Picker("", selection: $draft.apiProtocol) {
                        ForEach(AIAPIProtocol.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .frame(width: DesignTokens.Size.settingsFieldSmall)
                }
            }

            SettingsRow(
                title: "Base URL",
                subtitle: "不含 /chat/completions，通常以 /v1 结尾。非本机地址必须是 https。",
                icon: { SettingsRowIcon(systemImage: "link") }
            ) {
                TextField("", text: $draft.baseURL, prompt: Text("https://api.example.com/v1"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(width: DesignTokens.Size.settingsFieldMedium)
            }

            if isCustom {
                Toggle(isOn: $draft.requiresAPIKey) {
                    SettingsRow(
                        title: "需要 API Key",
                        subtitle: "本机运行的服务（Ollama、LM Studio）通常不需要。",
                        icon: { SettingsRowIcon(systemImage: "lock") }
                    )
                }
            }

            if draft.requiresAPIKey {
                SettingsRow(
                    title: "API Key",
                    subtitle: "只存在本机 Keychain，不会进偏好文件，也不会上传。",
                    icon: { SettingsRowIcon(systemImage: "key") }
                ) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Group {
                            if showKey {
                                TextField("", text: $apiKey, prompt: Text("sk-…"))
                            } else {
                                SecureField("", text: $apiKey, prompt: Text("sk-…"))
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(width: DesignTokens.Size.settingsFieldWide)

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .font(DesignTokens.Typography.compactIcon)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(showKey ? "隐藏密钥" : "显示密钥")
                        .help(showKey ? "隐藏" : "显示")
                    }
                }

                if let keyURL = draft.preset?.keyURL, let url = URL(string: keyURL) {
                    Link(destination: url) {
                        Label("去 \(draft.displayName) 获取 API Key", systemImage: "arrow.up.right.square")
                    }
                }
            }
        } header: {
            Text(isNew ? "添加服务商" : "服务商")
        }
    }

    // MARK: - 模型

    private var modelsSection: some View {
        Section {
            if draft.models.isEmpty {
                Text("还没有模型。手动输入模型名，或点「自动拉取」从服务商获取。")
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }

            ForEach(draft.models, id: \.self) { model in
                HStack {
                    Text(model)
                        .font(DesignTokens.Typography.rowTrailing)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        draft.removeModel(model)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(DesignTokens.Typography.compactIcon)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("移除模型 \(model)")
                    .help("移除")
                }
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                TextField("", text: $newModel, prompt: Text("输入模型名，如 gpt-4o"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .onSubmit(addTypedModel)
                Button("添加", action: addTypedModel)
                    .disabled(newModel.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack(spacing: DesignTokens.Spacing.md) {
                Button {
                    showModelPicker = true
                } label: {
                    Label("自动拉取模型…", systemImage: "arrow.down.circle")
                }
                .disabled(!canFetchModels)
                .help(canFetchModels ? "从服务商的 /models 接口获取并勾选" : "先填好 Base URL 和 API Key")

                if let suggested = suggestedToAdd, !suggested.isEmpty {
                    Menu {
                        ForEach(suggested, id: \.self) { model in
                            Button(model) { draft.addModel(model) }
                        }
                    } label: {
                        Label("常见模型", systemImage: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        } header: {
            Text("模型")
        } footer: {
            Text("这里添加的模型会出现在 AI 对话的模型选择里。")
        }
    }

    private var suggestedToAdd: [String]? {
        draft.preset?.suggestedModels.filter { !draft.models.contains($0) }
    }

    private var canFetchModels: Bool {
        !draft.resolvedBaseURL.isEmpty
            && (!draft.requiresAPIKey
                || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func addTypedModel() {
        if draft.addModel(newModel) { newModel = "" }
    }

    // MARK: - 连接测试

    private var testSection: some View {
        Section {
            SettingsRow(
                title: "连接测试",
                subtitle: testMessage ?? "用第一个模型发一条最短消息，确认配置能通。",
                icon: { SettingsRowIcon(systemImage: "bolt.horizontal") }
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button("测试", action: runTest)
                        .disabled(isTesting || draft.models.isEmpty)
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else if testMessage != nil {
                        Image(systemName: testSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(
                                testSucceeded ? DesignTokens.Colors.success : DesignTokens.Colors.destructive)
                    }
                }
            }
        }
    }

    private func runTest() {
        guard let model = draft.models.first else { return }
        let endpoint = draft.endpoint(model: model, apiKey: apiKey)
        isTesting = true
        testMessage = nil
        Task {
            do {
                let reply = try await AIService.testConnection(endpoint: endpoint)
                testSucceeded = true
                testMessage = "连接成功：\(reply.isEmpty ? "OK" : String(reply.prefix(40)))"
            } catch {
                testSucceeded = false
                testMessage = error.localizedDescription
            }
            isTesting = false
        }
    }

    // MARK: - 删除

    private var dangerSection: some View {
        Section {
            Button("删除此服务商…", role: .destructive) { confirmDelete = true }
        }
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack {
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.destructive)
                    .lineLimit(2)
            }
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "添加" : "保存", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding()
    }

    /// 至少要有地址；名称空了会回落到预设名，不拦
    private var canSave: Bool {
        !draft.resolvedBaseURL.isEmpty
    }

    private func save() {
        do {
            try AIProviderStore.setAPIKey(apiKey, for: draft)
        } catch {
            saveError = "Key 没能写入 Keychain：\(error.localizedDescription)"
            return
        }
        onSave(draft)
        dismiss()
    }
}

/// 自动拉取模型后的勾选弹窗
///
/// 已经添加过的模型默认勾上且不可取消（移除请回到列表里点减号），
/// 这样「添加所选」的语义始终是「新增」，不会因为一次手滑删掉已有的模型。
struct AIModelPickerSheet: View {

    let endpoint: AIEndpoint
    let alreadyAdded: Set<String>
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum LoadState {
        case loading
        case failed(String)
        case loaded([String])
    }

    @State private var state: LoadState = .loading
    @State private var selection: Set<String> = []
    @State private var filter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("选择要添加的模型")
                .font(.headline)

            switch state {
            case .loading:
                centered { ProgressView("正在获取…") }
            case .failed(let message):
                centered {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(DesignTokens.Typography.emptyStateIcon)
                            .foregroundStyle(.secondary)
                        Text(message)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") { load() }
                    }
                }
            case .loaded(let models):
                list(models)
            }

            HStack {
                if case .loaded(let models) = state {
                    Text("共 \(models.count) 个，已选 \(newSelectionCount) 个新增")
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加所选") {
                    // 保持服务商返回的顺序，而不是 Set 的随机顺序
                    if case .loaded(let models) = state {
                        onAdd(models.filter { selection.contains($0) && !alreadyAdded.contains($0) })
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newSelectionCount == 0)
            }
        }
        .padding()
        .frame(width: DesignTokens.Size.aiEditorWidth, height: DesignTokens.Size.aiModelPickerHeight)
        .task { load() }
    }

    private var newSelectionCount: Int {
        selection.subtracting(alreadyAdded).count
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ models: [String]) -> some View {
        let visible =
            filter.trimmingCharacters(in: .whitespaces).isEmpty
            ? models : models.filter { $0.localizedCaseInsensitiveContains(filter) }
        return VStack(spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                TextField("", text: $filter, prompt: Text("筛选模型"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                Button("全选") { selection.formUnion(visible) }
                Button("全不选") { selection = alreadyAdded }
            }
            List(visible, id: \.self) { model in
                Toggle(
                    isOn: Binding(
                        get: { selection.contains(model) },
                        set: { isOn in
                            if isOn { selection.insert(model) } else { selection.remove(model) }
                        })
                ) {
                    HStack {
                        Text(model).font(DesignTokens.Typography.rowTrailing)
                        if alreadyAdded.contains(model) {
                            Text("已添加")
                                .font(DesignTokens.Typography.rowTrailing)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(alreadyAdded.contains(model))
            }
            .overlay {
                if visible.isEmpty {
                    Text("没有匹配的模型").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func load() {
        state = .loading
        Task {
            do {
                let models = try await AIService.fetchModels(endpoint: endpoint)
                selection = alreadyAdded
                state = .loaded(models)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
