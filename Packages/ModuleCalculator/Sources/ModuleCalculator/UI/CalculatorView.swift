// CalculatorView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 计算器模块视图
struct CalculatorView: View {

    let engine: CalcEngine

    @State private var expression = ""
    @State private var result: String?

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            // 标题
            HStack {
                Image(systemName: "plus.forwardslash.minus")
                    .font(DesignTokens.Typography.headerIcon)
                Text("计算器")
                    .font(DesignTokens.Typography.panelTitle)
            }
            .foregroundStyle(DesignTokens.Colors.textPrimary)

            // 表达式输入
            TextField("输入表达式…", text: $expression)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.searchField)
                .padding(DesignTokens.Spacing.xl)
                .background {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                        .fill(DesignTokens.Colors.cardFill)
                        .stroke(DesignTokens.Colors.cardStroke, lineWidth: 1)
                }
                .onSubmit {
                    if let calcResult = engine.evaluate(expression) {
                        result = calcResult.formatted
                    }
                }
                .onChange(of: expression) { _, newValue in
                    result = engine.evaluate(newValue)?.formatted
                }

            // 结果显示
            if let result {
                HStack {
                    Text("= \(result)")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        EventBus.shared.post(CopyToClipboardEvent(text: result))
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .padding(DesignTokens.Spacing.xl)
                .background {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                        .fill(DesignTokens.Colors.cardFill)
                }
            }

            Spacer()

            // 提示
            Text("支持四则运算、括号、单位换算（如 100 km to mi）")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
