// WordCounterTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 字数统计工具
///
/// 参考 Fasty word-counter 布局：
/// 输入区 → 统计卡片行 → 语言特征
struct WordCounterTool: DevTool {
    let id = "wordcount"
    let name = "字数统计"
    let icon = "textformat.123"
    let keywords = ["字数", "统计", "word count", "字符数", "行数"]
    let description = "统计字符数、单词数、行数、预估阅读时长"

    func makeView() -> AnyView {
        AnyView(WordCounterView())
    }
}

struct WordCounterView: View {
    @State private var input = ""

    private var charCount: Int { input.count }
    private var charCountNoSpaces: Int { input.filter { !$0.isWhitespace }.count }
    private var wordCount: Int {
        input.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
    private var lineCount: Int {
        input.isEmpty ? 0 : input.components(separatedBy: "\n").count
    }
    private var byteCount: Int { input.utf8.count }
    private var readingTime: String {
        let cpm = 500  // 中文阅读速度（字/分钟）
        let minutes = max(1, charCountNoSpaces / cpm)
        return "约 \(minutes) 分钟"
    }

    private var chineseCount: Int { input.filter { $0.isChineseCharacter }.count }
    private var englishCount: Int { input.filter { $0.isASCII && $0.isLetter }.count }
    private var digitCount: Int { input.filter { $0.isNumber }.count }
    private var punctuationCount: Int { input.filter { $0.isPunctuation }.count }

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
                statCard("字符", charCount)
                statCard("不含空格", charCountNoSpaces)
                statCard("单词", wordCount)
                statCard("行数", lineCount)
                statCard("字节", byteCount)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)

            // 语言特征行
            HStack(spacing: DesignTokens.Spacing.md) {
                miniStat("中文", chineseCount)
                miniStat("英文", englishCount)
                miniStat("数字", digitCount)
                miniStat("标点", punctuationCount)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "book")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(readingTime)
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

// MARK: - Character 扩展
private extension Character {
    var isChineseCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
            || (0x3400...0x4DBF).contains(scalar.value)
    }
}
