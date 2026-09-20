// SQLFormatterView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct SQLFormatterView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var indent = 2
    @State private var statementCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    formatSQL()
                } label: {
                    Label("格式化", systemImage: "text.alignleft")
                }.buttonStyle(.borderedProminent).controlSize(.small)

                Button {
                    compactSQL()
                } label: {
                    Label("压缩", systemImage: "arrow.down.right.and.arrow.up.left")
                }.buttonStyle(.bordered).controlSize(.small)

                Button {
                    EventBus.shared.post(CopyToClipboardEvent(text: output.isEmpty ? input : output))
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }.buttonStyle(.bordered).controlSize(.small)

                Button {
                    input = ""; output = ""; statementCount = 0
                } label: {
                    Label("清空", systemImage: "trash")
                }.buttonStyle(.bordered).controlSize(.small)

                Spacer()

                Picker("缩进", selection: $indent) {
                    Text("2 空格").tag(2)
                    Text("4 空格").tag(4)
                }.pickerStyle(.segmented).frame(width: 140)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider().opacity(0.3)

            // 编辑区（双栏）
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("输入 SQL")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: $input)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)

                VStack(alignment: .leading, spacing: 0) {
                    Text("输出")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: .constant(output))
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)
            }

            Divider().opacity(0.3)

            // 状态栏
            HStack(spacing: DesignTokens.Spacing.lg) {
                if statementCount > 0 {
                    Text("\(statementCount) 条语句")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                if !input.isEmpty {
                    Text(SQLFormatterLogic.byteSize(input))
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                if !output.isEmpty {
                    Text("已格式化")
                        .font(.caption).foregroundStyle(.green)
                }
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .onChange(of: input) { _, _ in autoFormat() }
    }

    private func autoFormat() {
        guard !input.isEmpty else { output = ""; statementCount = 0; return }
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
