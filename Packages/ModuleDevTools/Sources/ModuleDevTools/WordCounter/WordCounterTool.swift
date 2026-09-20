// WordCounterTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// 字数统计工具
struct WordCounterTool: DevTool {
    let id = "wordcount"
    let name = "字数统计"
    let icon = "textformat.123"
    let keywords = ["字数", "统计", "word count", "字符数", "行数"]
    let description = "统计字符数、单词数、行数"

    func makeView() -> AnyView {
        AnyView(WordCounterView())
    }
}

struct WordCounterView: View {
    @State private var input = ""

    private var charCount: Int { input.count }
    private var charCountNoSpaces: Int { input.replacingOccurrences(of: " ", with: "").count }
    private var wordCount: Int {
        input.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
    private var lineCount: Int {
        input.isEmpty ? 0 : input.components(separatedBy: "\n").count
    }
    private var byteCount: Int { input.utf8.count }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Text("字数统计")
                .font(DesignTokens.Typography.panelTitle)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextEditor(text: $input)
                .font(DesignTokens.Typography.code)
                .scrollContentBackground(.hidden)
                .padding(DesignTokens.Spacing.md)
                .background(DesignTokens.Colors.cardFill)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))

            HStack(spacing: DesignTokens.Spacing.xxl) {
                statItem("字符", value: charCount)
                statItem("不含空格", value: charCountNoSpaces)
                statItem("单词", value: wordCount)
                statItem("行数", value: lineCount)
                statItem("字节", value: byteCount)
            }
        }
        .padding(DesignTokens.Spacing.xl)
    }

    private func statItem(_ label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }
}
