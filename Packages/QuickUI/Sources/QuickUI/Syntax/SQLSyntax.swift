// SQLSyntax.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// SQL 的 tokenizer
///
/// 与 `JSONSyntax` 同样是单趟扫描、不建语法树。SQL 的方言差异很大，所以关键词表
/// 刻意保守：只收录各方言都认的那些，认不出来的一律按普通标识符处理 ——
/// 把表名染成关键字颜色，比少染一个关键字更难看。
public enum SQLSyntax {

    /// 高亮用的关键字集合
    ///
    /// **与 `SQLFormatterLogic` 的关键词表是两件事**：那张表决定「哪些词后面要换行」，
    /// 这张表决定「哪些词涂成关键字色」。两者的取舍标准不同（一个管排版、一个管颜色），
    /// 所以不强行合并 —— 合并的结果是改排版会顺手改掉颜色。
    static let keywords: Set<String> = [
        // 查询
        "SELECT", "FROM", "WHERE", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET",
        "DISTINCT", "AS", "UNION", "ALL", "EXISTS", "IN", "BETWEEN", "LIKE", "IS",
        "ASC", "DESC", "WITH", "RETURNING", "WINDOW", "OVER", "PARTITION",
        // 连接
        "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS", "ON", "USING",
        // 增删改
        "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "REPLACE", "MERGE",
        // 结构
        "CREATE", "ALTER", "DROP", "TABLE", "INDEX", "VIEW", "TRIGGER", "SCHEMA",
        "DATABASE", "COLUMN", "PRIMARY", "FOREIGN", "KEY", "REFERENCES", "UNIQUE",
        "CONSTRAINT", "DEFAULT", "CHECK", "CASCADE", "RESTRICT", "TEMPORARY", "IF",
        // 条件与逻辑
        "AND", "OR", "NOT", "CASE", "WHEN", "THEN", "ELSE", "END", "NULL", "TRUE", "FALSE",
        // 事务
        "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "SAVEPOINT",
        // 聚合
        "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "CAST", "NULLIF"
    ]

    /// 把文本切成 token
    public static func tokens(in text: String) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if SyntaxScanner.isWhitespace(character) {
                index = text.index(after: index)
                continue
            }

            // 行注释：-- 到行尾
            if character == "-", peek(text, index, offset: 1) == "-" {
                let end = endOfLine(in: text, from: index)
                tokens.append(SyntaxToken(range: index..<end, kind: .comment))
                index = end
                continue
            }

            // 块注释：/* ... */
            if character == "/", peek(text, index, offset: 1) == "*" {
                let end = endOfBlockComment(in: text, from: index)
                tokens.append(SyntaxToken(range: index..<end, kind: .comment))
                index = end
                continue
            }

            // 字符串：单引号，内部的 '' 表示一个单引号
            if character == "'" {
                let end = endOfSQLString(in: text, from: index)
                tokens.append(SyntaxToken(range: index..<end, kind: .string))
                index = end
                continue
            }

            // 被引号括起来的标识符：双引号或反引号（保留大小写、可能是关键字同形词）
            if character == "\"" || character == "`" {
                let end = SyntaxScanner.endOfQuotedString(
                    in: text, from: index, quote: character, escape: false)
                tokens.append(SyntaxToken(range: index..<end, kind: .key))
                index = end
                continue
            }

            if character.isNumber {
                let end = endOfNumber(in: text, from: index)
                tokens.append(SyntaxToken(range: index..<end, kind: .number))
                index = end
                continue
            }

            if character.isLetter || character == "_" {
                let end = endOfWord(in: text, from: index)
                let word = String(text[index..<end]).uppercased()
                // 大小写不敏感：`select` 与 `SELECT` 都算关键字
                let kind: SyntaxTokenKind = keywords.contains(word) ? .keyword : .plain
                tokens.append(SyntaxToken(range: index..<end, kind: kind))
                index = end
                continue
            }

            if "()[],;.*=<>+-/%!|&".contains(character) {
                let end = text.index(after: index)
                tokens.append(SyntaxToken(range: index..<end, kind: .punctuation))
                index = end
                continue
            }

            let end = text.index(after: index)
            tokens.append(SyntaxToken(range: index..<end, kind: .plain))
            index = end
        }

        return tokens
    }

    // MARK: - 内部

    private static func peek(_ text: String, _ index: String.Index, offset: Int) -> Character? {
        guard let target = text.index(index, offsetBy: offset, limitedBy: text.endIndex),
            target < text.endIndex
        else { return nil }
        return text[target]
    }

    private static func endOfLine(in text: String, from start: String.Index) -> String.Index {
        var index = start
        while index < text.endIndex, text[index] != "\n" {
            index = text.index(after: index)
        }
        return index
    }

    private static func endOfBlockComment(
        in text: String, from start: String.Index
    )
        -> String.Index
    {
        var index = text.index(start, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
        while index < text.endIndex {
            if text[index] == "*", peek(text, index, offset: 1) == "/" {
                return text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
            }
            index = text.index(after: index)
        }
        // 未闭合：染到末尾
        return text.endIndex
    }

    /// SQL 字符串的结束位置
    ///
    /// SQL 用两个连续单引号表示字符串里的单引号（`'it''s'`），不是反斜杠转义。
    /// 按反斜杠处理会让 `'it''s'` 提前结束，把后面半句也染成字符串。
    private static func endOfSQLString(in text: String, from start: String.Index) -> String.Index {
        var index = text.index(after: start)
        while index < text.endIndex {
            guard text[index] == "'" else {
                index = text.index(after: index)
                continue
            }
            let next = text.index(after: index)
            if next < text.endIndex, text[next] == "'" {
                // '' 是一个转义的单引号，字符串继续
                index = text.index(after: next)
                continue
            }
            return next
        }
        return text.endIndex
    }

    private static func endOfNumber(in text: String, from start: String.Index) -> String.Index {
        var index = start
        while index < text.endIndex {
            let character = text[index]
            let isNumeric =
                character.isNumber || character == "." || character == "e"
                || character == "E" || character == "-" || character == "+"
            guard isNumeric else { break }
            index = text.index(after: index)
        }
        return index
    }

    private static func endOfWord(in text: String, from start: String.Index) -> String.Index {
        var index = start
        while index < text.endIndex, SyntaxScanner.isWordCharacter(text[index]) {
            index = text.index(after: index)
        }
        return index
    }
}
