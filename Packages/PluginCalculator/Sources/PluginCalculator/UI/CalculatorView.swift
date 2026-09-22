// CalculatorView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 计算器插件视图
///
/// 参考 Fasty calc-pad 布局：左侧多行输入，右侧逐行结果（点结果即可复制）。
/// 两栏共用同一条固定行高（`DesignTokens.Size.calculatorLineHeight`），所以第 N 行结果
/// 永远和第 N 行输入对齐 —— 输入框因此不能用 `TextEditor`，见 `CalcInputView` 的说明。
struct CalculatorView: View {

    let engine: CalcEngine

    /// 输入文本归插件所有：主面板与分离窗口共享同一份，分离时内容自然带过去
    @Bindable var buffer: TextBuffer

    private var input: String {
        get { buffer.text }
        nonmutating set { buffer.text = newValue }
    }
    @State private var lineResults: [(line: String, result: String?)] = []
    @State private var copiedIndex: Int?

    /// 输入行与结果行共用的行高
    private static let lineHeight = DesignTokens.Size.calculatorLineHeight

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                inputColumn
                // 没输入时不摆空的第二栏：一道分隔线劈开一大片空白，看起来像坏了
                if !input.isEmpty {
                    Divider().opacity(0.3)
                    resultColumn
                }
            }

            Divider().opacity(0.3)

            statusBar
        }
        .onChange(of: input) { _, _ in evaluateLines() }
        .onAppear { evaluateLines() }
    }

    // MARK: - 输入

    /// 多行输入。空的时候盖一层占位提示（不能放进 NSTextView 里，那是输入内容）
    private var inputColumn: some View {
        ZStack(alignment: .topLeading) {
            CalcInputView(text: $buffer.text, lineHeight: Self.lineHeight)

            if input.isEmpty {
                Text("输入表达式，每行一个…")
                    .font(DesignTokens.Typography.calculator)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.xs)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 结果

    /// 逐行结果。**每一行都占位**（没有结果的空行也占一条），下标才对得上输入行
    private var resultColumn: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(Array(lineResults.enumerated()), id: \.offset) { index, item in
                    if let result = item.result {
                        CalculatorResultRow(
                            result: result,
                            isCopied: copiedIndex == index,
                            lineHeight: Self.lineHeight,
                            onCopy: { copy(result, index: index) }
                        )
                    } else {
                        // 没结果的行也必须占位，否则后面的结果会往上串行
                        Color.clear.frame(height: Self.lineHeight)
                    }
                }
            }
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .scrollIndicators(.never)
        .frame(width: DesignTokens.Size.calculatorResultWidth)
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            let validCount = lineResults.filter { $0.result != nil }.count
            if validCount > 0 {
                Text("\(validCount) 个结果")
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Text("支持四则运算、函数、括号、单位换算")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    // MARK: - 动作

    /// 逐行计算
    private func evaluateLines() {
        // 每轮都从设置里取显示选项：小数位数与千分位开关在面板开着时也能立刻生效
        let options = CalcPreferences.displayOptions()
        let lines = input.components(separatedBy: "\n")
        lineResults = lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return (line: line, result: nil) }
            let result = engine.evaluate(trimmed, options: options)
            return (line: line, result: result?.formatted)
        }
    }

    /// 点结果复制，并在 1.5 秒内把图标换成对勾作为反馈
    private func copy(_ result: String, index: Int) {
        EventBus.shared.post(CopyToClipboardEvent(text: result))
        copiedIndex = index
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if copiedIndex == index { copiedIndex = nil }
        }
    }
}

// MARK: - 结果行

/// 一行结果：整块可点复制，悬停给一层淡底
private struct CalculatorResultRow: View {

    let result: String
    let isCopied: Bool
    let lineHeight: CGFloat
    let onCopy: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            Button(action: onCopy) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("= \(result)")
                        .font(DesignTokens.Typography.calculator)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)

                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(DesignTokens.Typography.inlineIcon)
                        .foregroundStyle(
                            isCopied
                                ? DesignTokens.Colors.success
                                : DesignTokens.Colors.textTertiary
                        )
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .frame(height: lineHeight)
                .background {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                        .fill(isHovered ? DesignTokens.Colors.rowHover : Color.clear)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("复制结果")
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .frame(height: lineHeight, alignment: .trailing)
    }
}
