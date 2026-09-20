// CalculatorView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 计算器模块视图
///
/// 参考 Fasty calc-pad 布局：
/// 多行输入 + 每行实时结果预览 + 变量赋值 + 计算历史
struct CalculatorView: View {

    let engine: CalcEngine

    @State private var input = ""
    @State private var lineResults: [(line: String, result: String?)] = []
    @State private var copiedIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            // 编辑区 + 结果区
            HStack(spacing: 0) {
                // 左侧：多行输入
                VStack(alignment: .leading, spacing: 0) {
                    Text("表达式")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: $input)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(maxWidth: .infinity)

                Divider().opacity(0.3)

                // 右侧：每行对应的计算结果
                ScrollView {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(lineResults.enumerated()), id: \.offset) { index, item in
                            HStack {
                                Spacer()
                                if let result = item.result {
                                    Button {
                                        EventBus.shared.post(CopyToClipboardEvent(text: result))
                                        copiedIndex = index
                                        Task { @MainActor in
                                            try? await Task.sleep(for: .seconds(1.5))
                                            if copiedIndex == index { copiedIndex = nil }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("= \(result)")
                                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                                .foregroundStyle(Color.accentColor)
                                            Image(
                                                systemName: copiedIndex == index ? "checkmark" : "doc.on.doc"
                                            )
                                            .font(.system(size: 9))
                                            .foregroundStyle(
                                                copiedIndex == index
                                                    ? .green : DesignTokens.Colors.textTertiary
                                            )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(height: 20)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                        }
                    }
                    .padding(.top, DesignTokens.Spacing.xs + 18)
                }
                .frame(width: 200)
            }

            Divider().opacity(0.3)

            // 底部提示和统计
            HStack(spacing: DesignTokens.Spacing.lg) {
                let validCount = lineResults.filter { $0.result != nil }.count
                if validCount > 0 {
                    Text("\(validCount) 个结果")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                }

                Text("支持四则运算、函数、括号、单位换算")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .onChange(of: input) { _, _ in evaluateLines() }
        .onAppear { evaluateLines() }
    }

    /// 逐行计算
    private func evaluateLines() {
        let lines = input.components(separatedBy: "\n")
        lineResults = lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return (line: line, result: nil) }
            let result = engine.evaluate(trimmed)
            return (line: line, result: result?.formatted)
        }
    }
}
