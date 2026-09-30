// SQLFormatterView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// SQL 格式化面板
///
/// 单栏原地编辑：`格式化` / `压缩` 直接改写同一个带实时 SQL 语法高亮与行号的编辑区，
/// 粘贴（⌘V / 右键粘贴 / 跨面板带入）时自动原地格式化；平时手动打字只做高亮不重排，避免光标跳动。
struct SQLFormatterView: View {

    private enum ActionState {
        case formatted
        case minified
    }

    /// 当前文本（唯一真相：主面板与分离窗口共享同一份，分离时内容自然带过去）
    @Bindable var buffer: TextBuffer

    private var text: String {
        get { buffer.text }
        nonmutating set { buffer.text = newValue }
    }

    /// 与设置页共用的持久化偏好
    @AppStorage(PluginSettingKey.SQLFormatter.indent) private var indent = 2
    @AppStorage(PluginSettingKey.SQLFormatter.keywordCase) private var keywordCaseRaw = "uppercase"
    @AppStorage(PluginSettingKey.SQLFormatter.wrapLines) private var wrapLines = true

    @State private var statementCount = 0
    @State private var lineCount = 0
    @State private var lastAction: ActionState?

    /// 粘贴检测或超级面板跳转时携带的初始文本
    @Environment(\.pluginContext) private var pluginContext

    private var resolvedKeywordCase: SQLFormatterLogic.KeywordCase {
        SQLFormatterLogic.KeywordCase(rawOrDefault: keywordCaseRaw)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider().opacity(0.3)

            CodeEditorView(
                text: $buffer.text,
                language: .sql,
                showsLineNumbers: true,
                wrapLines: wrapLines,
                placeholder: "粘贴或输入 SQL 语句，粘贴时自动原地格式化…",
                autoFocus: true,
                onPaste: {
                    formatSQL()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.3)

            statusBar
        }
        .onAppear {
            loadInitialText()
        }
        .onChange(of: pluginContext) { _, _ in
            loadInitialText()
        }
        .onChange(of: text) { _, _ in
            refreshStats()
        }
        .onChange(of: indent) { _, _ in
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            formatSQL()
        }
        .onChange(of: keywordCaseRaw) { _, _ in
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if lastAction == .minified {
                compactSQL()
            } else {
                formatSQL()
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
                EventBus.shared.post(CopyToClipboardEvent(text: text))
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(text.isEmpty)

            Button {
                clear()
            } label: {
                Label("清空", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(text.isEmpty)

            Toggle(isOn: $wrapLines) {
                Label("换行", systemImage: "text.wrap")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("自动换行")

            Spacer()

            Picker("", selection: $keywordCaseRaw) {
                Text("大写").tag("uppercase")
                Text("小写").tag("lowercase")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: DesignTokens.Size.settingsControl)
            .help("SQL 关键字大小写风格")

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
            .frame(width: DesignTokens.Size.settingsControlWide)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            if statementCount > 0 {
                Text("\(statementCount) 条语句")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            if lineCount > 0 {
                Text("\(lineCount) 行")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            if !text.isEmpty {
                Text(SQLFormatterLogic.byteSize(text))
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            if !text.isEmpty, let lastAction {
                Text(lastAction == .formatted ? "已格式化" : "已压缩")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.success)
            }
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    // MARK: - 动作

    /// 从导航上下文读取初始输入（粘贴检测自动跳转 / 超级面板带入），并自动原地格式化
    private func loadInitialText() {
        guard let initialQuery = pluginContext["query"], !initialQuery.isEmpty else {
            refreshStats()
            return
        }
        text = SQLFormatterLogic.format(
            initialQuery,
            indent: indent,
            keywordCase: resolvedKeywordCase
        )
        lastAction = .formatted
        refreshStats()
    }

    private func refreshStats() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statementCount = 0
            lineCount = 0
            lastAction = nil
            return
        }
        statementCount = SQLFormatterLogic.statementCount(in: text)
        lineCount = SQLFormatterLogic.lineCount(in: text)
    }

    private func formatSQL() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        text = SQLFormatterLogic.format(
            text,
            indent: indent,
            keywordCase: resolvedKeywordCase
        )
        lastAction = .formatted
        refreshStats()
    }

    private func compactSQL() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        text = SQLFormatterLogic.minify(text, keywordCase: resolvedKeywordCase)
        lastAction = .minified
        refreshStats()
    }

    private func clear() {
        text = ""
        statementCount = 0
        lineCount = 0
        lastAction = nil
    }
}
