// SQLFormatterLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// SQL 格式化的纯逻辑
///
/// 从视图里抽出来是为了能脱离 SwiftUI 单独测试 —— `Model/` 不允许 import
/// SwiftUI/AppKit（仓库红线，靠 grep 保证），视图只负责把结果写进 @State。
enum SQLFormatterLogic {

    /// 需要独占一行的双词关键字（按出现的词序匹配，大小写不敏感）
    ///
    /// 必须在单词关键字之前判断 —— 否则 `LEFT` 先被当成普通词处理，`JOIN`
    /// 再单独换行，多词子句就被拆散了。
    private static let twoWordClauses: Set<[String]> = [
        ["INSERT", "INTO"], ["DELETE", "FROM"], ["CREATE", "TABLE"],
        ["ALTER", "TABLE"], ["DROP", "TABLE"], ["GROUP", "BY"],
        ["ORDER", "BY"], ["UNION", "ALL"], ["LEFT", "JOIN"],
        ["RIGHT", "JOIN"], ["INNER", "JOIN"], ["OUTER", "JOIN"],
        ["CROSS", "JOIN"]
    ]

    /// 需要独占一行的单词关键字
    private static let clauseStarters: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "JOIN", "ON", "UNION",
        "HAVING", "VALUES", "UPDATE", "SET", "LIMIT", "OFFSET",
        "CASE", "WHEN", "THEN", "ELSE", "END", "AS"
    ]

    /// 格式化：关键字独占一行并统一大写
    ///
    /// 先做词法分析，字符串字面量、引号标识符、注释整体透传 —— 绝不能像旧的
    /// 正则写法那样把换行插进 `'FROM'` 这类字符串值里。
    ///
    /// 顺带把每行前导空格清掉，否则双击格式化的结果会一层层往外漂。
    /// `indent` 当前不产生实际缩进（保持与旧行为一致）。
    static func format(_ input: String, indent: Int) -> String {
        let tokens = tokenize(input).filter {
            if case .whitespace = $0 { return false }
            return true
        }

        var lines: [String] = []
        var builder = LineBuilder()
        // 上一个产出的 token 是否「像标识符」—— 决定 `(` 是函数调用还是子查询开头
        var identLike = false

        var index = 0
        while index < tokens.count {
            switch tokens[index] {
            case .word(let word):
                let upper = word.uppercased()
                if index + 1 < tokens.count,
                    case .word(let nextWord) = tokens[index + 1],
                    twoWordClauses.contains([upper, nextWord.uppercased()])
                {
                    lines.append(builder.finish())
                    builder.token("\(upper) \(nextWord.uppercased())")
                    identLike = false
                    index += 2
                } else if clauseStarters.contains(upper) {
                    lines.append(builder.finish())
                    builder.token(upper)
                    identLike = false
                    index += 1
                } else {
                    builder.token(word)
                    identLike = true
                    index += 1
                }

            case .string, .quoted, .number, .blockComment:
                builder.token(tokens[index].literal)
                identLike = true
                index += 1

            case .lineComment:
                builder.token(tokens[index].literal)
                lines.append(builder.finish())
                identLike = false
                index += 1

            case .punctuation(let punctuation):
                switch punctuation {
                case ".":
                    // 限定名 `a.id` 与小数点紧贴两侧
                    builder.glue(punctuation)
                    identLike = true
                case "(":
                    if identLike {
                        builder.glue(punctuation)
                    } else {
                        builder.token(punctuation)
                        builder.glueNextToken()
                    }
                    identLike = false
                case ")":
                    builder.tight(punctuation)
                    identLike = true
                case ",":
                    builder.tight(punctuation)
                    identLike = false
                case ";":
                    builder.tight(punctuation)
                    lines.append(builder.finish())
                    identLike = false
                default:
                    builder.token(punctuation)
                    identLike = false
                }
                index += 1

            case .whitespace:
                index += 1
            }
        }
        lines.append(builder.finish())

        return lines
            .map { $0.trimmingCharacters(in: .init(charactersIn: " ")) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// 压缩：折行与连续空白归一成单个空格，字面量与注释原样保留
    static func minify(_ input: String) -> String {
        let tokens = tokenize(input).filter {
            if case .whitespace = $0 { return false }
            return true
        }

        var output = ""
        var glueNext = false
        var identLike = false

        func emit(_ text: String) {
            if !output.isEmpty, !glueNext, !output.hasSuffix(" ") { output += " " }
            output += text
            glueNext = false
        }
        func glue(_ text: String) {
            output += text
            glueNext = true
        }
        func tight(_ text: String) {
            if output.hasSuffix(" ") { output.removeLast() }
            output += text
            glueNext = false
        }

        for token in tokens {
            switch token {
            case .word, .string, .quoted, .number, .blockComment:
                emit(token.literal)
                identLike = !clauseStarters.contains(token.literal.uppercased())
            case .lineComment:
                emit(token.literal)
                identLike = false
            case .punctuation(let punctuation):
                switch punctuation {
                case ".":
                    glue(punctuation)
                    identLike = true
                case "(":
                    if identLike {
                        glue(punctuation)
                    } else {
                        emit(punctuation)
                        glueNext = true
                    }
                    identLike = false
                case ")", ",":
                    tight(punctuation)
                    identLike = punctuation == ")"
                case ";":
                    tight(punctuation)
                    output += " "
                default:
                    emit(punctuation)
                    identLike = false
                }
            case .whitespace:
                break
            }
        }
        return output.trimmingCharacters(in: .whitespaces)
    }

    /// 语句条数（按分号切分，忽略空段）
    static func statementCount(in input: String) -> Int {
        input.components(separatedBy: ";").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    /// 人类可读的字节数
    static func byteSize(_ text: String) -> String {
        let bytes = text.utf8.count
        if bytes < 1024 { return "\(bytes) B" }
        return String(format: "%.1f KB", Double(bytes) / 1024)
    }

    // MARK: - 词法分析

    /// SQL 词法单元
    private enum Token: Equatable {
        /// 不带引号的标识符/关键字（保留原大小写）
        case word(String)
        /// 单引号字符串字面量（含引号，整体透传）
        case string(String)
        /// 双引号/反引号标识符（含引号，整体透传）
        case quoted(String)
        /// 数字
        case number(String)
        /// 标点或运算符
        case punctuation(String)
        /// `--` 行注释
        case lineComment(String)
        /// `/* ... */` 块注释
        case blockComment(String)
        /// 空白
        case whitespace(String)

        var literal: String {
            switch self {
            case .word(let value), .string(let value), .quoted(let value),
                .number(let value), .punctuation(let value),
                .lineComment(let value), .blockComment(let value),
                .whitespace(let value):
                return value
            }
        }
    }

    /// 把 SQL 文本切成词法单元
    private static func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        var index = input.startIndex

        while index < input.endIndex {
            let character = input[index]

            if character.isWhitespace {
                let start = index
                while index < input.endIndex, input[index].isWhitespace {
                    index = input.index(after: index)
                }
                tokens.append(.whitespace(String(input[start..<index])))
                continue
            }

            if character == "'" {
                index = consumeQuotedSequence(input, start: index, quote: "'", into: &tokens) { .string($0) }
                continue
            }

            if character == "\"" {
                index = consumeQuotedSequence(input, start: index, quote: "\"", into: &tokens) { .quoted($0) }
                continue
            }

            if character == "`" {
                // MySQL 反引号标识符：到下一个反引号为止
                let start = index
                index = input.index(after: index)
                while index < input.endIndex, input[index] != "`" {
                    index = input.index(after: index)
                }
                if index < input.endIndex { index = input.index(after: index) }
                tokens.append(.quoted(String(input[start..<index])))
                continue
            }

            if character == "-",
                input.index(after: index) < input.endIndex,
                input[input.index(after: index)] == "-"
            {
                let start = index
                while index < input.endIndex, input[index] != "\n" {
                    index = input.index(after: index)
                }
                tokens.append(.lineComment(String(input[start..<index])))
                continue
            }

            if character == "/",
                input.index(after: index) < input.endIndex,
                input[input.index(after: index)] == "*"
            {
                let start = index
                index = input.index(index, offsetBy: 2, limitedBy: input.endIndex) ?? input.endIndex
                while index < input.endIndex,
                    !(input[index] == "*"
                      && input.index(after: index) < input.endIndex
                      && input[input.index(after: index)] == "/")
                {
                    index = input.index(after: index)
                }
                if index < input.endIndex {
                    index = input.index(index, offsetBy: 2, limitedBy: input.endIndex) ?? input.endIndex
                }
                tokens.append(.blockComment(String(input[start..<index])))
                continue
            }

            if character.isLetter || character == "_" {
                let start = index
                while index < input.endIndex,
                    input[index].isLetter || input[index].isNumber || input[index] == "_"
                {
                    index = input.index(after: index)
                }
                tokens.append(.word(String(input[start..<index])))
                continue
            }

            if character.isNumber {
                let start = index
                while index < input.endIndex, input[index].isNumber || input[index] == "." {
                    index = input.index(after: index)
                }
                tokens.append(.number(String(input[start..<index])))
                continue
            }

            // 双字符运算符优先
            let nextIndex = input.index(after: index)
            if nextIndex < input.endIndex {
                let two = String(character) + String(input[nextIndex])
                if ["<=", ">=", "<>", "!=", "||", "::"].contains(two) {
                    tokens.append(.punctuation(two))
                    index = input.index(after: nextIndex)
                    continue
                }
            }
            tokens.append(.punctuation(String(character)))
            index = nextIndex
        }

        return tokens
    }

    /// 消费带「双写引号」转义的序列（单引号字符串或双引号标识符）
    private static func consumeQuotedSequence(
        _ input: String,
        start: String.Index,
        quote: Character,
        into tokens: inout [Token],
        makeToken: (String) -> Token
    ) -> String.Index {
        var index = input.index(after: start)
        while index < input.endIndex {
            if input[index] == quote {
                let nextIndex = input.index(after: index)
                // 双写引号是转义，不是结束
                if nextIndex < input.endIndex, input[nextIndex] == quote {
                    index = input.index(after: nextIndex)
                    continue
                }
                index = nextIndex
                break
            }
            index = input.index(after: index)
        }
        tokens.append(makeToken(String(input[start..<index])))
        return index
    }

    // MARK: - 输出辅助

    /// 逐行累积输出：常规片段之间留一个空格，`.`/`(` 两侧与后文紧贴，`)`/`,` 紧贴前文
    private struct LineBuilder {
        private var line = ""
        private var glueNext = false

        /// 常规词法片段：与前文以单个空格分隔
        mutating func token(_ text: String) {
            if !line.isEmpty, !glueNext { line += " " }
            line += text
            glueNext = false
        }

        /// 紧贴输出，并让下一个片段继续紧贴
        mutating func glue(_ text: String) {
            line += text
            glueNext = true
        }

        /// 紧贴输出，下一个片段恢复正常间距
        mutating func tight(_ text: String) {
            line += text
            glueNext = false
        }

        mutating func glueNextToken() {
            glueNext = true
        }

        /// 取出当前行并重置；空行返回空串（由调用方过滤）
        mutating func finish() -> String {
            let finished = line
            line = ""
            glueNext = false
            return finished
        }
    }
}
