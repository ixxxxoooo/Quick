// MarkdownPreviewTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// Markdown 预览工具
///
/// 参考 Fasty markdown-preview 布局：
/// 工具栏（复制/清空）→ 左右双栏（编辑 + 预览）
struct MarkdownPreviewTool: DevTool {
    let id = "markdown"
    let name = "Markdown 预览"
    let icon = "text.badge.checkmark"
    let keywords = ["markdown", "md", "预览", "标记"]
    let description = "实时 Markdown 编辑与预览"

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

        > 引用文本

        ```
        let x = 42
        ```
        """

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

                if !input.isEmpty {
                    Text("\(input.count) 字符")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider().opacity(0.3)

            // 双栏：编辑 + 预览
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("编辑")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: $input)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)

                VStack(alignment: .leading, spacing: 0) {
                    Text("预览")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
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
