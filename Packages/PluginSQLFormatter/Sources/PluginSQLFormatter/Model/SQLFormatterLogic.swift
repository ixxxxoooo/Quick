// SQLFormatterLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// SQL 格式化的纯逻辑
///
/// 从视图里抽出来是为了能脱离 SwiftUI 单独测试 —— `Model/` 不允许 import
/// SwiftUI/AppKit（仓库红线，靠 grep 保证），视图只负责把结果写进 @State。
enum SQLFormatterLogic {

    /// 关键字大小写风格
    enum KeywordCase: String, CaseIterable, Sendable {
        case uppercase = "uppercase"
        case lowercase = "lowercase"

        init(rawOrDefault raw: String) {
            self = KeywordCase(rawValue: raw.lowercased()) ?? .uppercase
        }

        func apply(to text: String) -> String {
            switch self {
            case .uppercase: text.uppercased()
            case .lowercase: text.lowercased()
            }
        }
    }

    /// 单行字符软上限：超过此长度时，遇到逗号自动折行
    private static let maxLineLength = 72

    /// 需要独占一行的三词子句（必须在双词与单词关键字之前匹配）
    private static let threeWordClauses: Set<[String]> = [
        ["LEFT", "OUTER", "JOIN"], ["RIGHT", "OUTER", "JOIN"], ["FULL", "OUTER", "JOIN"],
        ["CREATE", "UNIQUE", "INDEX"], ["CREATE", "OR", "REPLACE"],
        ["INSERT", "OR", "REPLACE"], ["INSERT", "OR", "IGNORE"]
    ]

    /// 需要独占一行的双词子句（按出现的词序匹配，大小写不敏感）
    ///
    /// 必须在单词关键字之前判断 —— 否则 `LEFT` 先被当成普通词处理，`JOIN`
    /// 再单独换行，多词子句就被拆散了。
    private static let twoWordClauses: Set<[String]> = [
        ["INSERT", "INTO"], ["INSERT", "IGNORE"], ["DELETE", "FROM"], ["TRUNCATE", "TABLE"],
        ["CREATE", "TABLE"], ["ALTER", "TABLE"], ["DROP", "TABLE"],
        ["CREATE", "VIEW"], ["DROP", "VIEW"], ["CREATE", "INDEX"], ["DROP", "INDEX"],
        ["GROUP", "BY"], ["ORDER", "BY"], ["PARTITION", "BY"],
        ["UNION", "ALL"], ["UNION", "DISTINCT"], ["EXCEPT", "ALL"], ["INTERSECT", "ALL"],
        ["LEFT", "JOIN"], ["RIGHT", "JOIN"], ["INNER", "JOIN"], ["OUTER", "JOIN"],
        ["CROSS", "JOIN"], ["FULL", "JOIN"], ["NATURAL", "JOIN"],
        ["WITH", "RECURSIVE"], ["FOR", "UPDATE"], ["FETCH", "FIRST"], ["FETCH", "NEXT"]
    ]

    /// 顶层主子句关键字（独占一行，按当前括号层级基准缩进）
    private static let majorClauseStarters: Set<String> = [
        "SELECT", "FROM", "WHERE", "JOIN", "STRAIGHT_JOIN", "UNION", "EXCEPT", "INTERSECT",
        "HAVING", "VALUES", "UPDATE", "SET", "LIMIT", "OFFSET", "WITH", "RETURNING", "WINDOW"
    ]

    /// 从属子句关键字（独占一行，在当前括号基准缩进上 +1 级）
    private static let subClauseStarters: Set<String> = [
        "AND", "OR", "ON", "USING"
    ]

    /// 行内关键字（不触发换行，但随 `KeywordCase` 规范化大小写）
    private static let inlineKeywords: Set<String> = [
        "AS", "DISTINCT", "ALL", "IN", "IS", "NOT", "NULL", "TRUE", "FALSE",
        "LIKE", "ILIKE", "RLIKE", "BETWEEN", "EXISTS", "ASC", "DESC",
        "OVER", "INTO", "TABLE", "INDEX", "VIEW", "DEFAULT", "PRIMARY",
        "KEY", "FOREIGN", "REFERENCES", "UNIQUE", "CHECK", "CONSTRAINT",
        "IF", "TEMPORARY", "CASCADE", "RESTRICT", "ONLY", "ROWS", "THEN",
        "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "CAST", "NULLIF", "IFNULL"
    ]

    /// 后接 `(` 时应保留一个空格的关键字（函数名不在其中，故 `COUNT(*)` 紧贴而 `IN (1, 2)` 留空）
    private static let keywordsWithSpaceBeforeParen: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "EXISTS", "VALUES",
        "SET", "ON", "USING", "HAVING", "WHEN", "THEN", "ELSE", "CASE", "AS",
        "JOIN", "UNION", "EXCEPT", "INTERSECT", "BY", "WITH"
    ]

    /// 括号类型：子查询块括号换行并缩进，普通行内括号保持紧凑
    private enum ParenKind {
        case subquery(savedMultilineSelect: Bool)
        case inline
    }

    // MARK: - 格式化

    /// 格式化：子句分行、层级缩进、长字段列表自动折行、关键字统一大小写
    ///
    /// 先做词法分析，字符串字面量、引号标识符、参数占位符与注释整体透传 ——
    /// 绝不把换行插进 `'FROM'` 这类字符串值里，也不拆散 `:param` / `#{id}`。
    static func format(
        _ input: String,
        indent: Int,
        keywordCase: KeywordCase = .uppercase
    ) -> String {
        let tokens = tokenize(input).filter {
            if case .whitespace = $0 { return false }
            return true
        }
        guard !tokens.isEmpty else { return "" }

        let indentUnit = String(repeating: " ", count: max(0, indent))
        var lines: [(level: Int, text: String)] = []
        var builder = LineBuilder()

        var subqueryDepth = 0
        var inlineParenDepth = 0
        var caseDepth = 0
        var currentLineLevel = 0
        var parenStack: [ParenKind] = []
        // 当前 SELECT 子句是否因字段过多/过长而启用「每字段一行」模式
        var multilineSelect = false
        // 上一个产出的 token 是否「像函数名/普通标识符」—— 决定 `(` 是紧贴还是留空格
        var identLike = false
        // `BETWEEN expr AND expr` 中的第一个 `AND` 留在行内，不当作 WHERE 子句折行
        var pendingBetween = false

        func flushLine(nextLevel: Int) {
            let text = builder.finish().trimmingCharacters(in: .init(charactersIn: " "))
            if !text.isEmpty {
                lines.append((level: currentLineLevel, text: text))
            }
            currentLineLevel = max(0, nextLevel)
        }

        var index = 0
        while index < tokens.count {
            switch tokens[index] {
            case .word(let word):
                let upper = word.uppercased()
                let baseLevel = subqueryDepth + caseDepth

                // 1. 三词子句
                if index + 2 < tokens.count,
                    case .word(let second) = tokens[index + 1],
                    case .word(let third) = tokens[index + 2],
                    threeWordClauses.contains([upper, second.uppercased(), third.uppercased()])
                {
                    multilineSelect = false
                    flushLine(nextLevel: baseLevel)
                    let phrase = "\(upper) \(second.uppercased()) \(third.uppercased())"
                    builder.token(keywordCase.apply(to: phrase))
                    identLike = false
                    pendingBetween = false
                    index += 3
                }
                // 2. 双词子句
                else if index + 1 < tokens.count,
                    case .word(let nextWord) = tokens[index + 1],
                    twoWordClauses.contains([upper, nextWord.uppercased()])
                {
                    multilineSelect = false
                    flushLine(nextLevel: baseLevel)
                    let phrase = "\(upper) \(nextWord.uppercased())"
                    builder.token(keywordCase.apply(to: phrase))
                    identLike = false
                    pendingBetween = false
                    index += 2
                }
                // 3. 主子句
                else if majorClauseStarters.contains(upper) {
                    flushLine(nextLevel: baseLevel)
                    builder.token(keywordCase.apply(to: upper))
                    if upper == "SELECT" {
                        multilineSelect = shouldBreakSelectItems(tokens: tokens, selectIndex: index)
                        if multilineSelect {
                            // 若紧跟 DISTINCT，把 DISTINCT 留在 SELECT 同一行再换行
                            if index + 1 < tokens.count,
                                case .word(let next) = tokens[index + 1],
                                next.uppercased() == "DISTINCT"
                            {
                                builder.token(keywordCase.apply(to: "DISTINCT"))
                                index += 1
                            }
                            flushLine(nextLevel: baseLevel + 1)
                        }
                    } else {
                        multilineSelect = false
                    }
                    identLike = false
                    pendingBetween = false
                    index += 1
                }
                // 4. 从属子句（AND / OR / ON / USING）
                else if subClauseStarters.contains(upper) {
                    if upper == "AND", pendingBetween {
                        pendingBetween = false
                        builder.token(keywordCase.apply(to: upper))
                    } else if inlineParenDepth > 0, builder.count < maxLineLength {
                        // 行内短括号条件（如 `(a = 1 AND b = 2)`）未超长时保持行内，超长再换行
                        builder.token(keywordCase.apply(to: upper))
                    } else {
                        let extraIndent = multilineSelect ? 2 : 1
                        flushLine(nextLevel: baseLevel + extraIndent)
                        builder.token(keywordCase.apply(to: upper))
                    }
                    identLike = false
                    index += 1
                }
                // 5. CASE ... WHEN ... THEN ... ELSE ... END
                else if upper == "CASE" {
                    builder.token(keywordCase.apply(to: upper))
                    caseDepth += 1
                    identLike = false
                    index += 1
                } else if upper == "WHEN" || upper == "ELSE" {
                    let selectExtra = multilineSelect ? 1 : 0
                    let whenLevel = subqueryDepth + selectExtra + max(1, caseDepth)
                    flushLine(nextLevel: whenLevel)
                    builder.token(keywordCase.apply(to: upper))
                    identLike = false
                    index += 1
                } else if upper == "END" {
                    let wasInCase = caseDepth > 0
                    caseDepth = max(0, caseDepth - 1)
                    if wasInCase {
                        let selectExtra = multilineSelect ? 1 : 0
                        flushLine(nextLevel: subqueryDepth + selectExtra + caseDepth)
                    }
                    builder.token(keywordCase.apply(to: upper))
                    identLike = false
                    index += 1
                }
                // 6. 行内关键字与普通标识符
                else {
                    if upper == "BETWEEN" {
                        pendingBetween = true
                    }
                    let formattedWord = inlineKeywords.contains(upper)
                        ? keywordCase.apply(to: upper) : word
                    builder.token(formattedWord)
                    identLike = !keywordsWithSpaceBeforeParen.contains(upper)
                    index += 1
                }

            case .string, .quoted, .number, .blockComment:
                builder.token(tokens[index].literal)
                identLike = true
                index += 1

            case .lineComment:
                let commentLevel = subqueryDepth + caseDepth + (multilineSelect ? 1 : 0)
                if !builder.isEmpty {
                    builder.token(tokens[index].literal)
                    flushLine(nextLevel: commentLevel)
                } else {
                    builder.token(tokens[index].literal)
                    flushLine(nextLevel: commentLevel)
                }
                identLike = false
                index += 1

            case .punctuation(let punctuation):
                switch punctuation {
                case ".", "::":
                    // 限定名 `a.id` 与类型转换 `a::text` 紧贴两侧
                    builder.glue(punctuation)
                    identLike = true
                case "(":
                    let isSubquery = containsSubqueryClause(tokens: tokens, openParenIndex: index)
                    if identLike {
                        builder.glue(punctuation)
                    } else {
                        builder.token(punctuation)
                    }
                    if isSubquery {
                        parenStack.append(.subquery(savedMultilineSelect: multilineSelect))
                        multilineSelect = false
                        subqueryDepth += 1
                        flushLine(nextLevel: subqueryDepth + caseDepth)
                    } else {
                        parenStack.append(.inline)
                        inlineParenDepth += 1
                        builder.glueNextToken()
                    }
                    identLike = false
                case ")":
                    let kind = parenStack.popLast() ?? .inline
                    switch kind {
                    case .subquery(let savedMultiline):
                        subqueryDepth = max(0, subqueryDepth - 1)
                        multilineSelect = savedMultiline
                        flushLine(nextLevel: subqueryDepth + caseDepth + (multilineSelect ? 1 : 0))
                        builder.token(punctuation)
                    case .inline:
                        inlineParenDepth = max(0, inlineParenDepth - 1)
                        builder.tight(punctuation)
                    }
                    identLike = true
                case ",":
                    builder.tight(punctuation)
                    let baseLevel = subqueryDepth + caseDepth
                    if multilineSelect, inlineParenDepth == 0, caseDepth == 0 {
                        flushLine(nextLevel: baseLevel + 1)
                    } else if builder.count >= maxLineLength {
                        let wrapLevel = baseLevel + (multilineSelect ? 1 : 0) + max(1, min(inlineParenDepth, 2))
                        flushLine(nextLevel: wrapLevel)
                    }
                    identLike = false
                case ";":
                    builder.tight(punctuation)
                    subqueryDepth = 0
                    inlineParenDepth = 0
                    caseDepth = 0
                    multilineSelect = false
                    parenStack.removeAll()
                    pendingBetween = false
                    flushLine(nextLevel: 0)
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
        flushLine(nextLevel: 0)

        return lines
            .map { String(repeating: indentUnit, count: $0.level) + $0.text }
            .joined(separator: "\n")
    }

    /// 判断 `SELECT` 子句是否应当将字段列表拆分为每行一个字段（顶层字段 >= 4 个或总字符数 > `maxLineLength`）
    private static func shouldBreakSelectItems(tokens: [Token], selectIndex: Int) -> Bool {
        var depth = 0
        var topLevelCommas = 0
        var charCount = 6
        var index = selectIndex + 1

        while index < tokens.count {
            switch tokens[index] {
            case .punctuation("("):
                depth += 1
                charCount += 1
            case .punctuation(")"):
                if depth == 0 { return topLevelCommas >= 3 || charCount > maxLineLength }
                depth -= 1
                charCount += 1
            case .punctuation(";"):
                if depth == 0 { return topLevelCommas >= 3 || charCount > maxLineLength }
            case .punctuation(",") where depth == 0:
                topLevelCommas += 1
                charCount += 2
                if topLevelCommas >= 3 { return true }
            case .word(let word) where depth == 0:
                let upper = word.uppercased()
                if majorClauseStarters.contains(upper)
                    || ["LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "FULL", "NATURAL", "GROUP", "ORDER", "FOR", "FETCH"].contains(upper)
                {
                    return topLevelCommas >= 3 || charCount > maxLineLength
                }
                charCount += word.count + 1
            default:
                charCount += tokens[index].literal.count + 1
            }
            if charCount > maxLineLength && topLevelCommas >= 1 {
                return true
            }
            index += 1
        }
        return topLevelCommas >= 3 || charCount > maxLineLength
    }

    /// 判断 `(` 内部同层是否包含子查询主子句（如 `SELECT`）
    private static func containsSubqueryClause(tokens: [Token], openParenIndex: Int) -> Bool {
        var depth = 1
        var index = openParenIndex + 1
        while index < tokens.count, depth > 0 {
            switch tokens[index] {
            case .punctuation("("):
                depth += 1
            case .punctuation(")"):
                depth -= 1
            case .word(let word) where depth == 1:
                let upper = word.uppercased()
                if upper == "SELECT" || upper == "WITH" {
                    return true
                }
            default:
                break
            }
            index += 1
        }
        return false
    }

    // MARK: - 压缩

    /// 压缩：折行与连续空白归一成单个空格，字面量与注释原样保留
    static func minify(_ input: String, keywordCase: KeywordCase? = nil) -> String {
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
            case .word(let word):
                let upper = word.uppercased()
                let isKnownKeyword = majorClauseStarters.contains(upper)
                    || subClauseStarters.contains(upper)
                    || inlineKeywords.contains(upper)
                    || ["CASE", "WHEN", "ELSE", "END", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "FULL", "NATURAL", "GROUP", "ORDER", "PARTITION", "BY", "INSERT", "DELETE", "TRUNCATE", "CREATE", "ALTER", "DROP", "FOR", "FETCH", "FIRST", "NEXT", "RECURSIVE", "IGNORE"].contains(upper)
                let emitted = (isKnownKeyword && keywordCase != nil)
                    ? keywordCase!.apply(to: word) : word
                emit(emitted)
                identLike = !keywordsWithSpaceBeforeParen.contains(upper)
            case .string, .quoted, .number, .blockComment:
                emit(token.literal)
                identLike = true
            case .lineComment:
                emit(token.literal)
                identLike = false
            case .punctuation(let punctuation):
                switch punctuation {
                case ".", "::":
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

    // MARK: - 统计

    /// 语句条数（按分号切分，忽略空段）
    static func statementCount(in input: String) -> Int {
        input.components(separatedBy: ";").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    /// 文本行数（空串为 0）
    static func lineCount(in input: String) -> Int {
        guard !input.isEmpty else { return 0 }
        return input.components(separatedBy: "\n").count
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
        /// 双引号/反引号/方括号标识符或参数占位符（整体透传）
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
                let start = index
                index = input.index(after: index)
                while index < input.endIndex, input[index] != "`" {
                    index = input.index(after: index)
                }
                if index < input.endIndex { index = input.index(after: index) }
                tokens.append(.quoted(String(input[start..<index])))
                continue
            }

            // SQL Server / SQLite 方括号标识符：[table_name]
            if character == "[" {
                let start = index
                index = input.index(after: index)
                while index < input.endIndex, input[index] != "]" {
                    index = input.index(after: index)
                }
                if index < input.endIndex { index = input.index(after: index) }
                tokens.append(.quoted(String(input[start..<index])))
                continue
            }

            // MyBatis / 模板占位符：#{...} 或 ${...}
            if (character == "#" || character == "$"),
                input.index(after: index) < input.endIndex,
                input[input.index(after: index)] == "{"
            {
                let start = index
                index = input.index(index, offsetBy: 2, limitedBy: input.endIndex) ?? input.endIndex
                while index < input.endIndex, input[index] != "}" {
                    index = input.index(after: index)
                }
                if index < input.endIndex { index = input.index(after: index) }
                tokens.append(.quoted(String(input[start..<index])))
                continue
            }

            // PostgreSQL 位置参数 / 变量：$1, $param
            if character == "$",
                input.index(after: index) < input.endIndex,
                input[input.index(after: index)].isLetter
                    || input[input.index(after: index)].isNumber
                    || input[input.index(after: index)] == "_"
            {
                let start = index
                index = input.index(after: index)
                while index < input.endIndex,
                    input[index].isLetter || input[index].isNumber || input[index] == "_"
                {
                    index = input.index(after: index)
                }
                tokens.append(.quoted(String(input[start..<index])))
                continue
            }

            // MySQL / SQL Server 变量：@var, @@global_var
            if character == "@" {
                let start = index
                index = input.index(after: index)
                if index < input.endIndex, input[index] == "@" {
                    index = input.index(after: index)
                }
                while index < input.endIndex,
                    input[index].isLetter || input[index].isNumber || input[index] == "_"
                {
                    index = input.index(after: index)
                }
                tokens.append(.quoted(String(input[start..<index])))
                continue
            }

            // 命名参数 :param（排除 :: 与 :=）
            if character == ":" {
                let next = input.index(after: index)
                if next < input.endIndex,
                    input[next].isLetter || input[next] == "_"
                {
                    let start = index
                    index = next
                    while index < input.endIndex,
                        input[index].isLetter || input[index].isNumber || input[index] == "_"
                    {
                        index = input.index(after: index)
                    }
                    tokens.append(.quoted(String(input[start..<index])))
                    continue
                }
            }

            // 行注释：-- 到行尾（注意使用 isNewline 以兼容 \r\n 扩展字素簇）
            if character == "-",
                input.index(after: index) < input.endIndex,
                input[input.index(after: index)] == "-"
            {
                let start = index
                while index < input.endIndex, !input[index].isNewline {
                    index = input.index(after: index)
                }
                tokens.append(.lineComment(String(input[start..<index])))
                continue
            }

            // 块注释：/* ... */
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

            // 三字符运算符（如 <=>、->>、#>>）
            if let thirdIndex = input.index(index, offsetBy: 3, limitedBy: input.endIndex) {
                let three = String(input[index..<thirdIndex])
                if ["<=>", "->>", "#>>"].contains(three) {
                    tokens.append(.punctuation(three))
                    index = thirdIndex
                    continue
                }
            }

            // 双字符运算符
            let nextIndex = input.index(after: index)
            if nextIndex < input.endIndex {
                let two = String(character) + String(input[nextIndex])
                if ["<=", ">=", "<>", "!=", "||", "::", ":=", "->", "#>", "<<", ">>", "~*", "!~"].contains(two) {
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

    /// 消费带「双写引号」或「反斜杠」转义的序列（单引号字符串或双引号标识符）
    private static func consumeQuotedSequence(
        _ input: String,
        start: String.Index,
        quote: Character,
        into tokens: inout [Token],
        makeToken: (String) -> Token
    ) -> String.Index {
        var index = input.index(after: start)
        while index < input.endIndex {
            if input[index] == "\\" {
                let nextIndex = input.index(after: index)
                index = nextIndex < input.endIndex ? input.index(after: nextIndex) : input.endIndex
                continue
            }
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

        var isEmpty: Bool { line.isEmpty }
        var count: Int { line.count }

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
