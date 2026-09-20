// WordCounterView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct WordCounterView: View {
    @State private var input = ""

    /// 计数规则全在模型层，视图只负责展示
    private var stats: WordCounterLogic.Stats { WordCounterLogic.stats(for: input) }

    var body: some View {
        VStack(spacing: 0) {
            // 输入区
            TextEditor(text: $input)
                .font(DesignTokens.Typography.code)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("输入或粘贴文本…")
                            .font(DesignTokens.Typography.code)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.top, DesignTokens.Spacing.md)

            Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.lg)

            // 主统计卡片行
            HStack(spacing: DesignTokens.Spacing.md) {
                statCard("字符", stats.characterCount)
                statCard("不含空格", stats.characterCountNoSpaces)
                statCard("单词", stats.wordCount)
                statCard("行数", stats.lineCount)
                statCard("字节", stats.byteCount)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)

            // 语言特征行
            HStack(spacing: DesignTokens.Spacing.md) {
                miniStat("中文", stats.chineseCount)
                miniStat("英文", stats.englishCount)
                miniStat("数字", stats.digitCount)
                miniStat("标点", stats.punctuationCount)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "book")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(stats.readingTime)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.sm)
        }
    }

    private func statCard(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }

    private func miniStat(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("\(value)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }
}
