// SQLFormatterView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// SQL 格式化面板
///
/// 布局与 Fasty sql-formatter 一致：工具栏 → 编辑区（输入 / 输出）→ 状态栏。
/// 输出带 SQL 语法高亮，见 `CodeTextView`。
struct SQLFormatterView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var indent = 2
    @State private var statementCount = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider().opacity(0.3)

            HSplitView {
                editorPane(title: "输入") {
                    TextEditor(text: $input)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                        .padding(DesignTokens.Spacing.sm)
                }

                editorPane(title: "输出") {
                    CodeTextView(output, language: .sql, placeholder: "格式化结果会显示在这里")
                }
            }

            Divider().opacity(0.3)

            statusBar
        }
        .onChange(of: input) { _, _ in autoFormat() }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button {
                formatSQL()
            } label: {
                Label("格式化", systemImage: "text.alignleft")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                compactSQL()
            } label: {
                Label("压缩", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                EventBus.shared.post(CopyToClipboardEvent(text: output.isEmpty ? input : output))
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                input = ""
                output = ""
                statementCount = 0
            } label: {
                Label("清空", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            // 标签自己写：分段控件自带标签会被挤成竖排窄条
            Text("缩进")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Picker("", selection: $indent) {
                Text("2 空格").tag(2)
                Text("4 空格").tag(4)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    // MARK: - 编辑区

    private func editorPane<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.sm)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 200)
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            if statementCount > 0 {
                Text("\(statementCount) 条语句")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            if !input.isEmpty {
                Text(SQLFormatterLogic.byteSize(input))
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            if !output.isEmpty {
                Text("已格式化")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.success)
            }
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    // MARK: - 动作

    private func autoFormat() {
        guard !input.isEmpty else {
            output = ""
            statementCount = 0
            return
        }
        formatSQL()
    }

    private func formatSQL() {
        output = SQLFormatterLogic.format(input, indent: indent)
        statementCount = SQLFormatterLogic.statementCount(in: input)
    }

    private func compactSQL() {
        output = SQLFormatterLogic.minify(input)
    }
}
