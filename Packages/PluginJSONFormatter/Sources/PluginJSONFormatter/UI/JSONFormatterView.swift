// JSONFormatterView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// JSON 格式化面板
///
/// 布局与 Fasty json-formatter 一致：工具栏 → 编辑区（输入 / 输出）→ 状态栏。
///
/// 输入用普通 `TextEditor`（编辑手感第一），输出用 `CodeTextView` 做**语法高亮**的
/// 只读渲染 —— 分工的理由见 `CodeTextView` 的说明。
struct JSONFormatterView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var errorMessage: String?
    /// 缩进风格持久化：设置页里的「JSON 缩进」改的就是它
    @AppStorage(PluginSettingKey.JSONFormatter.indent) private var indent = 2
    @State private var nodeCount = 0

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
                    CodeTextView(output, language: .json, placeholder: "格式化结果会显示在这里")
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
                format()
            } label: {
                Label("格式化", systemImage: "text.alignleft")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                compact()
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
                errorMessage = nil
                nodeCount = 0
            } label: {
                Label("清空", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            // 分段控件自带标签时会被挤成竖排的窄条（曾经的样式缺陷），
            // 所以标签自己写，控件只负责选择
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

    /// 一个编辑栏：标题 + 内容
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
            if nodeCount > 0 {
                Text("\(nodeCount) 个节点")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            if !input.isEmpty {
                Text(JSONFormatterLogic.byteSize(input))
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            if let error = errorMessage {
                Text(error)
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.destructive)
            } else if !output.isEmpty {
                Text("有效 JSON")
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
            errorMessage = nil
            nodeCount = 0
            return
        }
        format()
    }

    private func format() {
        guard let result = try? JSONFormatterLogic.prettyPrint(input, indent: indent) else {
            errorMessage = "无效的 JSON"
            nodeCount = 0
            return
        }
        errorMessage = nil
        nodeCount = result.nodeCount
        output = result.text
    }

    private func compact() {
        guard let text = try? JSONFormatterLogic.minify(input) else {
            errorMessage = "无效的 JSON"
            return
        }
        errorMessage = nil
        output = text
    }
}
