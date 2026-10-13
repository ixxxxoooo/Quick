// ChatMarkdownView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 把 `ChatMarkdown` 解析出的块渲染成视图
struct ChatMarkdownView: View {

    let text: String

    var body: some View {
        let blocks = ChatMarkdown.parse(text)
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: ChatMarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(text)
        case .heading(let level, let text):
            inlineText(text)
                .font(level <= 2 ? DesignTokens.Typography.panelTitle : DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        case .bullet(let text, let indent):
            listRow(marker: "•", text: text, indent: indent)
        case .numbered(let number, let text, let indent):
            listRow(marker: "\(number).", text: text, indent: indent)
        case .quote(let text):
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                RoundedRectangle(cornerRadius: DesignTokens.Spacing.xxs)
                    .fill(DesignTokens.Colors.border)
                    .frame(width: DesignTokens.Spacing.xs)
                inlineText(text)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        case .code(let language, let code):
            ChatCodeBlockView(language: language, code: code)
        case .rule:
            Rectangle()
                .fill(DesignTokens.Colors.separator)
                .frame(height: DesignTokens.Spacing.hairline)
        }
    }

    private func listRow(marker: String, text: String, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
            Text(marker)
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            inlineText(text)
        }
        .padding(.leading, CGFloat(indent) * DesignTokens.Spacing.xxl)
    }

    private func inlineText(_ text: String) -> some View {
        Text(ChatMarkdown.inline(text))
            .font(DesignTokens.Typography.rowTitle)
            .foregroundStyle(DesignTokens.Colors.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 代码块：语言标签 + 复制按钮 + 横向可滚动的等宽代码
struct ChatCodeBlockView: View {

    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "代码")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer()
                Button(action: copy) {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("复制代码")
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(DesignTokens.Typography.code)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.bottom, DesignTokens.Spacing.lg)
                    .fixedSize()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: DesignTokens.Spacing.hairline)
        )
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(DesignTokens.Duration.copyFeedback))
            copied = false
        }
    }
}
