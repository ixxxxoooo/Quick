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
    /// 输入文本归插件所有：主面板与分离窗口共享同一份，分离时内容自然带过去
    @Bindable var buffer: TextBuffer

    private var input: String {
        get { buffer.text }
        nonmutating set { buffer.text = newValue }
    }
    @State private var output = ""
    @State private var indent = 2
    @State private var statementCount = 0
    /// 大输入走防抖 + 后台计算，小输入同步算（见 `Debouncer`）
    @State private var debouncer = Debouncer()

    /// 粘贴检测跳转时携带的初始文本
    @Environment(\.pluginContext) private var pluginContext

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider().opacity(0.3)

            HSplitView {
                editorPane(title: "输入") {
                    TextEditor(text: $buffer.text)
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
        // 缩进档位改了要立刻按新缩进重排：以前只有改文本才会重排，切换后输出纹丝不动
        .onChange(of: indent) { _, _ in if !input.isEmpty { formatSQL() } }
        .onDisappear { debouncer.cancel() }
        .onAppear {
            // 从导航上下文读取初始输入（粘贴检测自动跳转场景）。
            // **带了初始文本就覆盖**：缓冲区是插件级的、会跨次保留，只在「空」时加载会被旧内容挡住。
            if let initialQuery = pluginContext["query"], !initialQuery.isEmpty {
                input = initialQuery
            }
        }
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
            debouncer.cancel()
            output = ""
            statementCount = 0
            return
        }
        formatSQL()
    }

    /// 格式化 + 统计语句数；大输入后台算（点「格式化」与边打边排共用这一条路径）
    private func formatSQL() {
        let text = input
        let width = indent
        debouncer.schedule(
            weight: text.utf8.count,
            work: {
                (SQLFormatterLogic.format(text, indent: width), SQLFormatterLogic.statementCount(in: text))
            },
            apply: { formatted, count in
                output = formatted
                statementCount = count
            })
    }

    private func compactSQL() {
        debouncer.cancel()
        output = SQLFormatterLogic.minify(input)
    }
}
