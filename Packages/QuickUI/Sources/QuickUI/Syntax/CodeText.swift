// CodeText.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 语法高亮的渲染
///
/// 把 tokenizer 的输出（位置 + 类别）翻译成 `AttributedString`。
/// 颜色全部取自 `DesignTokens.Colors.Syntax`，视图里不出现颜色字面量。
public enum SyntaxHighlighter {

    /// 给一段文本上色
    ///
    /// - Parameters:
    ///   - text: 原始文本
    ///   - language: 语言（决定用哪个 tokenizer）
    /// - Returns: 带颜色的富文本；字符内容与输入完全一致
    public static func attributed(_ text: String, language: CodeLanguage) -> AttributedString {
        var attributed = AttributedString(text)
        // 先把整体设成正文色，再按 token 覆盖 —— 这样未分类的字符也有确定的颜色，
        // 不会继承到调用方的样式
        attributed.foregroundColor = DesignTokens.Colors.textPrimary

        for token in language.tokens(in: text) {
            guard let range = Range(token.range, in: attributed) else { continue }
            attributed[range].foregroundColor = color(for: token.kind)
        }
        return attributed
    }

    /// token 类别 → 颜色
    public static func color(for kind: SyntaxTokenKind) -> Color {
        switch kind {
        case .plain: DesignTokens.Colors.textPrimary
        case .key: DesignTokens.Colors.Syntax.key
        case .string: DesignTokens.Colors.Syntax.string
        case .number: DesignTokens.Colors.Syntax.number
        case .literal: DesignTokens.Colors.Syntax.literal
        case .keyword: DesignTokens.Colors.Syntax.keyword
        case .comment: DesignTokens.Colors.Syntax.comment
        case .punctuation: DesignTokens.Colors.textSecondary
        }
    }
}

// MARK: - 只读高亮视图

/// 只读的语法高亮代码视图
///
/// ## 为什么输出用只读渲染，而不是带高亮的 `TextEditor`
///
/// `TextEditor` 可以绑定 `AttributedString`（macOS 26 起原生支持），但那样在每次
/// 输入后重建属性会打断光标与选区 —— 用户正在编辑时高亮一跳、光标跑到末尾，
/// 比没有高亮更难受。
///
/// 所以分工明确：
/// - **输入**用普通的 `TextEditor`（纯文本，编辑手感第一）
/// - **输出**用这个只读视图（高亮第一，反正它本来也不接受编辑）
///
/// 要动的是「读格式化结果」，高亮正好长在最该看的地方。
public struct CodeTextView: View {

    private let text: String
    private let language: CodeLanguage
    private let placeholder: String

    public init(_ text: String, language: CodeLanguage, placeholder: String = "") {
        self.text = text
        self.language = language
        self.placeholder = placeholder
    }

    public var body: some View {
        ScrollView {
            if text.isEmpty {
                Text(placeholder)
                    .font(DesignTokens.Typography.code)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignTokens.Spacing.md)
            } else {
                Text(SyntaxHighlighter.attributed(text, language: language))
                    .font(DesignTokens.Typography.code)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignTokens.Spacing.md)
            }
        }
    }
}
