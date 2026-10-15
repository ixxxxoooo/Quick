// AIChatView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// AI 对话主视图：左侧会话栏 + 右侧对话
public struct AIChatView: View {

    let controller: AIChatController

    public init(controller: AIChatController) {
        self.controller = controller
    }

    public var body: some View {
        HStack(spacing: 0) {
            if controller.isSidebarVisible {
                ChatSidebarView(controller: controller)
                    .frame(width: DesignTokens.Size.aiChatSidebarWidth)
                Rectangle()
                    .fill(DesignTokens.Colors.hairline)
                    .frame(width: DesignTokens.Spacing.hairline)
            }
            ChatConversationView(controller: controller)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 右侧对话区：顶栏 + 消息 + 输入框
struct ChatConversationView: View {

    let controller: AIChatController

    @State private var composerHeight = DesignTokens.Size.aiChatComposerMinHeight
    @State private var scrollPosition = ScrollPosition(edge: .bottom)

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ZStack(alignment: .bottom) {
                if let session = controller.current, !session.isEmpty {
                    messageList(session)
                } else {
                    emptyState
                }

                if let undo = controller.pendingUndo {
                    undoToast(undo)
                        .padding(.bottom, DesignTokens.Spacing.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Motion.animation(.snappy), value: controller.pendingUndo?.id)

            composer
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Button {
                controller.perform(.toggleSidebar)
            } label: {
                Image(systemName: "sidebar.left")
                    .font(DesignTokens.Typography.headerButtonMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(
                        width: DesignTokens.Size.aiChatRowHeight,
                        height: DesignTokens.Size.aiChatRowHeight
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("显示 / 隐藏会话栏 (⌘B)")
            .accessibilityLabel("显示或隐藏会话栏")

            Text(controller.current?.title ?? ChatSession.untitled)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: DesignTokens.Size.aiChatRowHeight + DesignTokens.Spacing.md)
    }

    // MARK: - 消息

    private func messageList(_ session: ChatSession) -> some View {
        let lastID = session.messages.last?.id
        let generating = controller.generatingIDs.contains(session.id)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                ForEach(session.messages) { message in
                    ChatMessageView(
                        message: message,
                        isLast: message.id == lastID,
                        isStreaming: generating && message.id == lastID && message.role == .assistant,
                        isCopied: controller.copiedID == message.id,
                        onCopy: { controller.copy(messageID: message.id) },
                        onRegenerate: { controller.regenerate() }
                    )
                    .equatable()
                }
            }
            .frame(maxWidth: DesignTokens.Size.aiChatColumnMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DesignTokens.Spacing.xxl)
            .padding(.vertical, DesignTokens.Spacing.lg)
        }
        // 换会话重建滚动视图：初始位置落在底部，而不是沿用上一个会话的偏移
        .id(session.id)
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .onChange(of: session.messages.count) { _, _ in
            scrollPosition.scrollTo(edge: .bottom)
        }
    }

    // MARK: - 空状态 / 引导

    @ViewBuilder
    private var emptyState: some View {
        if controller.choices.isEmpty {
            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "key.horizontal")
                    .font(DesignTokens.Typography.emptyStateIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("还没有可用的模型")
                    .font(DesignTokens.Typography.rowTitle)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text("添加一个服务商并填入 API Key，就可以在这里对话")
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Button("前往设置 › AI 服务") {
                    EventBus.shared.post(
                        ShowPaletteSettingsEvent(hostTab: SettingsTab.aiService.rawValue))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, DesignTokens.Spacing.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "sparkles")
                    .font(DesignTokens.Typography.emptyStateIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("有什么想聊的？")
                    .font(DesignTokens.Typography.rowTitle)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text("↵ 发送   ⇧↵ 换行   ⌘N 新对话   ⌘[ ⌘] 切换会话")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 删除撤销

    private func undoToast(_ session: ChatSession) -> some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Text("已删除「\(session.title)」")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
            Button("撤销") { controller.undoDelete() }
                .buttonStyle(.plain)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.progress)
                .focusable(false)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(Capsule().fill(DesignTokens.Colors.capsuleFill))
        .overlay(Capsule().strokeBorder(DesignTokens.Colors.capsuleStroke, lineWidth: DesignTokens.Spacing.hairline))
    }

    // MARK: - 输入区

    private var composer: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ChatComposer(
                text: Binding(get: { controller.draft }, set: { controller.draft = $0 }),
                height: $composerHeight,
                placeholder: "发消息…",
                focusToken: controller.composerFocusToken,
                onSubmit: { controller.send() }
            )
            .frame(height: composerHeight)

            HStack(spacing: DesignTokens.Spacing.md) {
                modelMenu
                Spacer(minLength: 0)
                sendButton
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: DesignTokens.Spacing.hairline)
        )
        .frame(maxWidth: DesignTokens.Size.aiChatColumnMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    private var modelMenu: some View {
        let selected = controller.currentChoice
        let groups = Dictionary(grouping: controller.choices, by: \.providerName)
        let order = controller.choices.map(\.providerName).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        return Menu {
            ForEach(order, id: \.self) { provider in
                Section(provider) {
                    ForEach(groups[provider] ?? []) { choice in
                        Button {
                            controller.setModel(choice.ref)
                        } label: {
                            if choice == selected {
                                Label(choice.model, systemImage: "checkmark")
                            } else {
                                Text(choice.model)
                            }
                        }
                    }
                }
            }
        } label: {
            Text(selected?.model ?? "选择模型")
                .font(DesignTokens.Typography.keyCap)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .disabled(controller.choices.isEmpty)
        .help("切换模型")
    }

    private var sendButton: some View {
        let generating = controller.isGeneratingCurrent
        let canSend = !controller.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && controller.currentChoice != nil
        return Button {
            if generating, let id = controller.currentID {
                controller.stop(id)
            } else {
                controller.send()
            }
        } label: {
            Image(systemName: generating ? "stop.circle.fill" : "arrow.up.circle.fill")
                .font(DesignTokens.Typography.headerIcon)
                .foregroundStyle(
                    generating || canSend
                        ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!generating && !canSend)
        .help(generating ? "停止生成 (Esc)" : "发送 (↵)")
        .accessibilityLabel(generating ? "停止生成" : "发送")
    }
}
