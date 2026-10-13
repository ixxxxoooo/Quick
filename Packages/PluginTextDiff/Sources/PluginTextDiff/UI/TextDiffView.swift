// TextDiffView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 文本对比视图
///
/// 左右两个**可编辑的代码编辑器**：打字即上色（语法高亮），行尾换行按差异标红 / 绿底。
/// 两个编辑器关闭软换行、共用同一条固定行高、垂直滚动同步，所以第 N 行和第 N 行严格对齐 ——
/// 这正是「编辑器式的对比」，而不是把结果另起一段铺在下面。
struct TextDiffView: View {

    /// 两栏文本归插件所有：主面板与分离窗口共享，分离时内容带过去
    @Bindable var bufferA: TextBuffer
    @Bindable var bufferB: TextBuffer

    private var textA: String {
        get { bufferA.text }
        nonmutating set { bufferA.text = newValue }
    }

    private var textB: String {
        get { bufferB.text }
        nonmutating set { bufferB.text = newValue }
    }

    @State private var diffResult: [TextDiffLogic.DiffLine] = []
    @State private var addedCount = 0
    @State private var removedCount = 0
    /// 左右两栏的逐行底色：随文本与选项变化时算一次，不在 `body` 里每次重算
    @State private var leftStates: [CodeEditorView.LineState] = []
    @State private var rightStates: [CodeEditorView.LineState] = []

    /// 是否开启自动换行（与插件设置同步）
    @AppStorage(PluginSettingKey.TextDiff.wrapLines) private var wrapLines = false

    /// 忽略空白 / 大小写（与设置页同一个键，两处改动互相同步）
    @AppStorage(PluginSettingKey.TextDiff.ignoreWhitespace) private var ignoreWhitespace = false
    @AppStorage(PluginSettingKey.TextDiff.ignoreCase) private var ignoreCase = false

    /// 语法高亮语言。对比任意文本时默认纯文本
    @State private var language: CodeLanguage = .plain

    /// 两个编辑器的垂直滚动同步
    @State private var scrollSync = EditorScrollSync()

    private typealias LineType = TextDiffLogic.DiffLine.LineType

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider().opacity(DesignTokens.Opacity.divider)

            HSplitView {
                editorColumn(text: $bufferA.text, title: "原文", states: leftStates, role: .leading)
                editorColumn(text: $bufferB.text, title: "修改后", states: rightStates, role: .trailing)
            }
        }
        .onAppear { computeDiff() }
        .onChange(of: textA) { _, _ in computeDiff() }
        .onChange(of: textB) { _, _ in computeDiff() }
        .onChange(of: ignoreWhitespace) { _, _ in computeDiff() }
        .onChange(of: ignoreCase) { _, _ in computeDiff() }
        .onDisappear { scrollSync.detach() }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button {
                swapTexts()
            } label: {
                Label("互换", systemImage: "arrow.left.arrow.right")
            }.buttonStyle(.bordered).controlSize(.small)

            Button {
                copyDiff()
            } label: {
                Label("复制差异", systemImage: "doc.on.doc")
            }.buttonStyle(.bordered).controlSize(.small)
                .disabled(diffResult.isEmpty)

            Button {
                clear()
            } label: {
                Label("清空", systemImage: "trash")
            }.buttonStyle(.bordered).controlSize(.small)

            Toggle(isOn: $wrapLines) {
                Label("换行", systemImage: "text.wrap")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("自动换行。开启后长行会折成多行，左右两栏不再严格逐行对齐")

            Toggle(isOn: $ignoreWhitespace) {
                Label("忽略空白", systemImage: "space")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("忽略行首尾空白，行内连续空白视为一个")

            Toggle(isOn: $ignoreCase) {
                Label("忽略大小写", systemImage: "capslock")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("比较时不区分大小写")

            Picker("语法", selection: $language) {
                ForEach(CodeLanguage.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()

            Spacer()

            diffBadges
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    /// 差异统计标签
    @ViewBuilder
    private var diffBadges: some View {
        if textA.isEmpty && textB.isEmpty {
            EmptyView()
        } else if addedCount == 0 && removedCount == 0 && !textA.isEmpty {
            badge("完全相同", color: DesignTokens.Colors.success)
        } else {
            if removedCount > 0 {
                badge("-\(removedCount)", color: DesignTokens.Colors.destructive)
            }
            if addedCount > 0 {
                badge("+\(addedCount)", color: DesignTokens.Colors.success)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DesignTokens.Typography.keyCap)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(color.opacity(DesignTokens.Opacity.diffBand))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap))
    }

    // MARK: - 编辑栏

    private func editorColumn(
        text: Binding<String>,
        title: String,
        states: [CodeEditorView.LineState],
        role: EditorScrollSync.Role
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(DesignTokens.Typography.keyCap)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.xs)

            CodeEditorView(
                text: text,
                language: language,
                lineStates: states,
                showsLineNumbers: true,
                wrapLines: wrapLines,
                scrollSync: scrollSync,
                syncRole: role
            )
        }
        .frame(minWidth: DesignTokens.Size.diffPaneMinWidth)
    }

    // MARK: - 逐行状态

    private func states(for types: [LineType]) -> [CodeEditorView.LineState] {
        types.map { type in
            switch type {
            case .same: .none
            case .added: .added
            case .removed: .removed
            }
        }
    }

    // MARK: - 动作

    private func swapTexts() {
        let temp = textA
        textA = textB
        textB = temp
    }

    private func copyDiff() {
        EventBus.shared.post(CopyToClipboardEvent(text: TextDiffLogic.render(diffResult)))
    }

    private func clear() {
        textA = ""
        textB = ""
        diffResult = []
        addedCount = 0
        removedCount = 0
        leftStates = []
        rightStates = []
    }

    /// 当前生效的对比选项
    private var options: TextDiffLogic.Options {
        TextDiffLogic.Options(ignoreWhitespace: ignoreWhitespace, ignoreCase: ignoreCase)
    }

    /// 对比算法整体在模型层，视图只把结果搬进 `@State`
    private func computeDiff() {
        let result = TextDiffLogic.diff(textA, against: textB, options: options)
        diffResult = result.lines
        addedCount = result.addedCount
        removedCount = result.removedCount
        let sides = TextDiffLogic.sideLineStates(textA, against: textB, options: options)
        leftStates = states(for: sides.left)
        rightStates = states(for: sides.right)
    }
}
