// MarkdownPreviewView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct MarkdownPreviewView: View {
    /// 文本归插件所有：主面板与分离窗口共享同一份，分离时内容自然带过去
    @Bindable var buffer: TextBuffer

    private var input: String {
        get { buffer.text }
        nonmutating set { buffer.text = newValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    EventBus.shared.post(CopyToClipboardEvent(text: input))
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }.buttonStyle(.bordered).controlSize(.small)

                Button {
                    input = ""
                } label: {
                    Label("清空", systemImage: "trash")
                }.buttonStyle(.bordered).controlSize(.small)

                Spacer()

                if let countLabel = MarkdownPreviewLogic.characterCountLabel(for: input) {
                    Text(countLabel)
                        .font(DesignTokens.Typography.keyCap).foregroundStyle(
                            DesignTokens.Colors.textTertiary)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider().opacity(0.3)

            // 双栏：编辑 + 预览
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("编辑")
                        .font(DesignTokens.Typography.keyCap).foregroundStyle(
                            DesignTokens.Colors.textTertiary
                        )
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: $buffer.text)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)

                VStack(alignment: .leading, spacing: 0) {
                    Text("预览")
                        .font(DesignTokens.Typography.keyCap).foregroundStyle(
                            DesignTokens.Colors.textTertiary
                        )
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    ScrollView {
                        Text(LocalizedStringKey(input))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignTokens.Spacing.md)
                    }
                }
                .frame(minWidth: 200)
            }
        }
    }
}
