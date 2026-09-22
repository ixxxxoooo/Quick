// CalculatorView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 计算器插件视图（计算稿纸）
///
/// 上方是按时间倒序的历史：每条算式一行，表达式左对齐、结果右对齐、时间在最右，
/// 点一下即可复制结果。下方是一条输入栏，边打边显示结果，回车把这一条记进稿纸。
///
/// 历史由 `CalcHistoryStore` 持久化，跨启动保留；主搜索里回车求值也记同一条历史。
struct CalculatorView: View {

    let engine: CalcEngine

    /// 计算历史（持久化）
    let store: CalcHistoryStore

    /// 输入文本归插件所有：主面板与分离窗口共享同一份，分离时内容自然带过去
    @Bindable var buffer: TextBuffer

    /// 当前输入的实时结果
    @State private var liveResult: String?

    /// 输入栏焦点：进入稿纸就该能直接打字，不用先点一下
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !store.entries.isEmpty {
                toolbar
            }

            historyArea

            Rectangle()
                .fill(DesignTokens.Colors.hairline)
                .frame(height: DesignTokens.Size.hairline)

            inputBar
        }
        .onAppear {
            focusInput()
            updateLiveResult()
        }
        // 面板已经是 key 时 `didBecomeKey` 不会再发，所以两条路都要走：
        // onAppear 负责进入插件的那一刻，didBecomeKey 负责面板重新被激活。
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            focusInput()
        }
        .onChange(of: buffer.text) { _, _ in updateLiveResult() }
    }

    /// 把焦点交给输入栏
    ///
    /// **必须延后一拍。** `onAppear` 时窗口的初始焦点还在按 key view loop 决定，
    /// 此刻赋值会被随后的「第一个可聚焦控件」（头部的返回按钮）覆盖掉 —— 表现就是
    /// 焦点落在返回键上。等一个 runloop 再设，才轮得到我们。
    private func focusInput() {
        Task { @MainActor in
            isInputFocused = true
        }
    }

    // MARK: - 工具栏

    /// 历史计数与清空
    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text("\(store.entries.count) 条记录")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Spacer(minLength: 0)

            Button {
                store.clear()
            } label: {
                Image(systemName: "trash")
                    .font(DesignTokens.Typography.inlineIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("清空计算历史")
            .help("清空计算历史")
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    // MARK: - 历史

    @ViewBuilder
    private var historyArea: some View {
        if store.entries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(store.entries) { entry in
                        CalcHistoryRow(
                            entry: entry,
                            onCopy: { copy(entry) },
                            onDelete: { store.remove(entry.id) }
                        )
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "function")
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Text("还没有计算记录")
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text("在下方输入表达式，回车即可记下这一条")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 输入栏

    private var inputBar: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "function")
                .font(DesignTokens.Typography.inlineIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            TextField("计算公式", text: $buffer.text)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.calculator)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .focused($isInputFocused)
                .onSubmit(commit)

            Spacer(minLength: DesignTokens.Spacing.md)

            trailingResult
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.lg)
    }

    /// 输入栏右侧：有结果就显示结果，否则给一句提示
    @ViewBuilder
    private var trailingResult: some View {
        if let liveResult {
            Text("= \(liveResult)")
                .font(DesignTokens.Typography.calculator)
                .fontWeight(.medium)
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
        } else if !buffer.text.isEmpty {
            Text("无法计算")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        } else {
            Text("回车记录")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    // MARK: - 动作

    /// 实时求值：输入一变就算一次，结果为空时不显示
    private func updateLiveResult() {
        let trimmed = buffer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            liveResult = nil
            return
        }
        let options = CalcPreferences.displayOptions()
        liveResult = engine.evaluate(trimmed, options: options)?.formatted
    }

    /// 回车：把当前算式记进稿纸并清空输入，焦点留在输入栏
    private func commit() {
        let trimmed = buffer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let liveResult else { return }
        store.record(expression: trimmed, result: liveResult)
        buffer.text = ""
        isInputFocused = true
    }

    /// 点历史行：复制结果（HUD 由事件宿主负责提示）
    private func copy(_ entry: CalcHistoryEntry) {
        EventBus.shared.post(CopyToClipboardEvent(text: entry.result))
    }
}

// MARK: - 历史行

/// 一条计算历史：表达式在左上，时间在右上，结果右对齐在下一行
private struct CalcHistoryRow: View {

    let entry: CalcHistoryEntry
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
                Text(entry.expression)
                    .font(DesignTokens.Typography.calculator)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: DesignTokens.Spacing.md)

                Text(entry.timestamp, format: Self.timestampStyle)
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .fixedSize()
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                Spacer(minLength: 0)

                Text("= \(entry.result)")
                    .font(DesignTokens.Typography.calculator)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)

                if isHovered {
                    iconButton("doc.on.doc", label: "复制结果", action: onCopy)
                    iconButton("trash", label: "删除", action: onDelete)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                .fill(isHovered ? DesignTokens.Colors.rowHover : Color.clear)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(action: onCopy) {
                Label("复制结果", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func iconButton(
        _ systemName: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DesignTokens.Typography.inlineIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(
                    width: DesignTokens.Size.clipboardFavoriteButton,
                    height: DesignTokens.Size.clipboardFavoriteButton
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    /// 时间列的格式（只建一次）
    private static let timestampStyle = Date.FormatStyle(date: .numeric, time: .shortened)
}
