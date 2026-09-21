// JSONSyntax.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// JSON 的 tokenizer
///
/// 单趟扫描，不建语法树：这里只关心「这段字符该涂什么颜色」，不关心结构对不对 ——
/// 合法性由 `JSONFormatterLogic` 用 `JSONSerialization` 判定，两件事分开。
public enum JSONSyntax {

    /// 把文本切成 token
    ///
    /// 未闭合的字符串会一直染到文本末尾：正在输入 `"abc` 时高亮跟着走，
    /// 比整段突然掉回普通色更容易看出「引号还没配完」。
    public static func tokens(in text: String) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if SyntaxScanner.isWhitespace(character) {
                index = text.index(after: index)
                continue
            }

            if character == "\"" {
                let end = SyntaxScanner.endOfQuotedString(
                    in: text, from: index, quote: "\"", escape: true)
                // 后面跟着冒号的字符串是「键」，否则是「值」——两者的颜色不一样
                let kind: SyntaxTokenKind =
                    nextSignificantCharacter(in: text, from: end) == ":"
                    ? .key : .string
                tokens.append(SyntaxToken(range: index..<end, kind: kind))
                index = end
                continue
            }

            if character == "-" || character.isNumber {
                let end = endOfNumber(in: text, from: index)
                tokens.append(SyntaxToken(range: index..<end, kind: .number))
                index = end
                continue
            }

            if character.isLetter {
                let end = endOfWord(in: text, from: index)
                let word = text[index..<end]
                let kind: SyntaxTokenKind =
                    ["true", "false", "null"].contains(word) ? .literal : .plain
                tokens.append(SyntaxToken(range: index..<end, kind: kind))
                index = end
                continue
            }

            if "{}[],:".contains(character) {
                let end = text.index(after: index)
                tokens.append(SyntaxToken(range: index..<end, kind: .punctuation))
                index = end
                continue
            }

            // 其余字符（含非法输入）：染成普通文本，不打断扫描
            let end = text.index(after: index)
            tokens.append(SyntaxToken(range: index..<end, kind: .plain))
            index = end
        }

        return tokens
    }

    /// 跳过空白后的下一个字符（用于判断字符串是键还是值）
    private static func nextSignificantCharacter(
        in text: String, from start: String.Index
    )
        -> Character?
    {
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if !SyntaxScanner.isWhitespace(character) { return character }
            index = text.index(after: index)
        }
        return nil
    }

    /// 数字的结束位置
    ///
    /// 只按「可能出现在数字里的字符」扫描，不校验格式（`1.2.3` 会被整体染成数字）：
    /// 高亮层不做合法性判断，那件事有专门的判定。
    private static func endOfNumber(in text: String, from start: String.Index) -> String.Index {
        var index = start
        while index < text.endIndex {
            let character = text[index]
            let isNumeric =
                character.isNumber || character == "." || character == "-"
                || character == "+" || character == "e" || character == "E"
            guard isNumeric else { break }
            index = text.index(after: index)
        }
        return index
    }

    /// 标识符的结束位置
    private static func endOfWord(in text: String, from start: String.Index) -> String.Index {
        var index = start
        while index < text.endIndex, SyntaxScanner.isWordCharacter(text[index]) {
            index = text.index(after: index)
        }
        return index
    }
}
