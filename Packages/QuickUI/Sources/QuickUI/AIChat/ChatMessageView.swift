// ChatMessageView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 一条消息
///
/// `Equatable` + `.equatable()`：流式生成时每 40ms 只有**最后一条**消息的内容在变，
/// 前面几十条历史消息的输入没变，SwiftUI 据此直接跳过它们的 `body`，
/// 不然长对话每个 token 都要把整段历史重新解析一遍 Markdown。
struct ChatMessageView: View, Equatable {

    let message: ChatMessage
    /// 是不是会话里最后一条（只有最后一条显示「重新生成」）
    let isLast: Bool
    /// 是否正在流式生成这一条
    let isStreaming: Bool
    let isCopied: Bool
    let onCopy: () -> Void
    let onRegenerate: () -> Void

    @State private var isHovering = false

    nonisolated static func == (lhs: ChatMessageView, rhs: ChatMessageView) -> Bool {
        lhs.message == rhs.message && lhs.isLast == rhs.isLast
            && lhs.isStreaming == rhs.isStreaming && lhs.isCopied == rhs.isCopied
    }

    var body: some View {
        switch message.role {
        case .user: userBubble
        case .assistant: assistantBlock
        }
    }

    // MARK: - 用户

    private var userBubble: some View {
        HStack(spacing: 0) {
            Spacer(minLength: DesignTokens.Spacing.xxl * 2)
            Text(message.content)
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.vertical, DesignTokens.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .fill(DesignTokens.Colors.selection)
                )
                .frame(maxWidth: DesignTokens.Size.aiChatBubbleMaxWidth, alignment: .trailing)
        }
    }

    // MARK: - 助手

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if message.content.isEmpty && message.failure == nil {
                thinking
            } else if !message.content.isEmpty {
                ChatMarkdownView(text: message.content)
            }

            if let failure = message.failure {
                failureRow(failure)
            }

            if !isStreaming && !message.content.isEmpty {
                footer
                    .opacity(isHovering || isLast || isCopied ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var thinking: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            ProgressView()
                .controlSize(.small)
            Text("正在思考…")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    private func failureRow(_ failure: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DesignTokens.Typography.inlineIcon)
                .foregroundStyle(DesignTokens.Colors.warning)
            Text(failure)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if isLast {
                Button("重试", action: onRegenerate)
                    .buttonStyle(.plain)
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.progress)
                    .focusable(false)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.warning.opacity(DesignTokens.Opacity.tint))
        )
    }

    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            if let model = message.model {
                Text(model)
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
            footerButton(
                isCopied ? "已复制" : "复制", icon: isCopied ? "checkmark" : "doc.on.doc",
                action: onCopy)
            if isLast && message.failure == nil {
                footerButton("重新生成", icon: "arrow.clockwise", action: onRegenerate)
            }
        }
    }

    private func footerButton(_ title: String, icon: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(DesignTokens.Typography.keyCap)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
