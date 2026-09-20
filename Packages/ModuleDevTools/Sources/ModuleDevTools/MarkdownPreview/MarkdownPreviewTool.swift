// MarkdownPreviewTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// Markdown 预览工具
struct MarkdownPreviewTool: DevTool {
    let id = "markdown"
    let name = "Markdown 预览"
    let icon = "text.badge.checkmark"
    let keywords = ["markdown", "md", "预览", "标记"]
    let description = "实时预览 Markdown 文本"

    func makeView() -> AnyView {
        AnyView(MarkdownPreviewView())
    }
}

struct MarkdownPreviewView: View {
    @State private var input = """
        # 标题

        这是一段 **Markdown** 文本。

        - 列表项 1
        - 列表项 2

        `代码` 和 [链接](https://example.com)
        """

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Text("Markdown 预览")
                .font(DesignTokens.Typography.panelTitle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HSplitView {
                TextEditor(text: $input)
                    .font(DesignTokens.Typography.code)
                    .scrollContentBackground(.hidden)
                    .frame(minWidth: 200)

                ScrollView {
                    Text(LocalizedStringKey(input))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignTokens.Spacing.md)
                }
                .frame(minWidth: 200)
            }
        }
        .padding(DesignTokens.Spacing.xl)
    }
}
