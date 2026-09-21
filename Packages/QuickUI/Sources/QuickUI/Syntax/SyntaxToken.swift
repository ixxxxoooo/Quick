// SyntaxToken.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一个语法片段所属的类别
///
/// 只分显示需要的类别：颜色靠它决定，语义（是不是关键字）由各语言的 tokenizer 判定。
public enum SyntaxTokenKind: Sendable, CaseIterable {
    /// 无特殊含义的普通文本
    case plain
    /// 对象的键（JSON）/ 被引号括起来的标识符（SQL）
    case key
    /// 字符串字面量
    case string
    /// 数字字面量
    case number
    /// 字面量常量：`true` / `false` / `null`
    case literal
    /// 语言关键字
    case keyword
    /// 注释
    case comment
    /// 括号、逗号、冒号、运算符
    case punctuation
}

/// 一段被归类的文本
///
/// 用 `Range<String.Index>` 而不是 `NSRange`：tokenizer 是纯 Swift 的，
/// 不依赖 AppKit，也就不会把 Foundation 的范围类型混进来。
public struct SyntaxToken: Sendable, Equatable {

    public let range: Range<String.Index>
    public let kind: SyntaxTokenKind

    public init(range: Range<String.Index>, kind: SyntaxTokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// 编辑器支持的语言
public enum CodeLanguage: Sendable, Equatable {
    case json
    case sql

    /// 取该语言的 tokenizer
    func tokens(in text: String) -> [SyntaxToken] {
        switch self {
        case .json: JSONSyntax.tokens(in: text)
        case .sql: SQLSyntax.tokens(in: text)
        }
    }
}

/// 把文本切成 token 的公共工具
///
/// 两个 tokenizer 共用的扫描动作放这里：判断标识符字符、跳过空白、扫字符串。
/// 它们都不碰 UI，所以能被单独测试。
enum SyntaxScanner {

    /// 是否可以作为标识符的一部分（字母、数字、下划线）
    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// 是否为空白
    static func isWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\n" || character == "\t" || character == "\r"
    }

    /// 从 `start` 扫到字符串结束（不含结尾引号之后）
    ///
    /// - Parameters:
    ///   - text: 原文本
    ///   - start: 开引号的位置
    ///   - quote: 引号字符
    ///   - escape: 是否处理反斜杠转义（JSON 需要，SQL 的 `''` 另有规则）
    /// - Returns: 结束位置（指向结尾引号之后）；没有闭合引号时返回文本末尾
    static func endOfQuotedString(
        in text: String,
        from start: String.Index,
        quote: Character,
        escape: Bool
    ) -> String.Index {
        var index = text.index(after: start)
        while index < text.endIndex {
            let character = text[index]
            if escape, character == "\\" {
                // 跳过被转义的那个字符，否则 `"a\""` 会被当成提前闭合
                index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                continue
            }
            if character == quote {
                return text.index(after: index)
            }
            index = text.index(after: index)
        }
        return text.endIndex
    }
}
