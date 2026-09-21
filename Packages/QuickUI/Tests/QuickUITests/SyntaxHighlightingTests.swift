// SyntaxHighlightingTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import SwiftUI
import Testing

@testable import QuickUI

/// 把 token 还原成 (类别, 文本) 列表，便于断言
private func classified(_ text: String, _ language: CodeLanguage) -> [(SyntaxTokenKind, String)] {
    language.tokens(in: text).map { ($0.kind, String(text[$0.range])) }
}

@Suite("JSON 语法高亮")
struct JSONSyntaxTests {

    @Test("对象的键与字符串值分开染色")
    func keysAndValuesDiffer() {
        let tokens = classified(#"{"name": "quick"}"#, .json)

        #expect(tokens.contains { $0 == (.punctuation, "{") })
        #expect(tokens.contains { $0 == (.key, "\"name\"") })
        #expect(tokens.contains { $0 == (.punctuation, ":") })
        #expect(tokens.contains { $0 == (.string, "\"quick\"") })
        // 键与值必须落在不同类别，否则颜色一样、高亮就没意义
        let nameKind = tokens.first { $0.1 == "\"name\"" }?.0
        let valueKind = tokens.first { $0.1 == "\"quick\"" }?.0
        #expect(nameKind != valueKind)
    }

    @Test("键的判定跳过空白")
    func keyDetectionSkipsWhitespace() {
        // 冒号与字符串之间隔着空格、换行也要认出来是键
        #expect(classified("{\"a\" : 1}", .json).contains { $0 == (.key, "\"a\"") })
        #expect(classified("{\n  \"a\"\n  : 1\n}", .json).contains { $0 == (.key, "\"a\"") })
    }

    @Test("数组里的字符串是值，不是键")
    func arrayStringsAreValues() {
        let tokens = classified(#"["a", "b"]"#, .json)
        #expect(tokens.filter { $0.0 == .key }.isEmpty)
        #expect(tokens.filter { $0.0 == .string }.count == 2)
    }

    @Test("数字与字面量")
    func numbersAndLiterals() {
        let tokens = classified(#"{"n": -12.5e3, "b": true, "z": null}"#, .json)
        #expect(tokens.contains { $0 == (.number, "-12.5e3") })
        #expect(tokens.contains { $0 == (.literal, "true") })
        #expect(tokens.contains { $0 == (.literal, "null") })
    }

    @Test("转义的引号不会提前结束字符串")
    func escapedQuoteDoesNotEndString() {
        // `"a\"b"` 是一个字符串；按第一个 \" 结束的话，后面的 b" 会被当成别的 token
        let tokens = classified(#"{"k": "a\"b"}"#, .json)
        #expect(tokens.contains { $0 == (.string, #""a\"b""#) })
    }

    @Test("未闭合的字符串一直染到末尾")
    func unterminatedStringRunsToEnd() {
        let tokens = classified(#"{"k": "abc"#, .json)
        #expect(tokens.contains { $0 == (.string, "\"abc") })
    }

    @Test("中文与 emoji 不会被切开")
    func handlesNonASCII() {
        let tokens = classified(#"{"城市": "北京 🌆"}"#, .json)
        #expect(tokens.contains { $0 == (.key, "\"城市\"") })
        #expect(tokens.contains { $0 == (.string, "\"北京 🌆\"") })
    }

    @Test("空文本没有 token")
    func emptyTextHasNoTokens() {
        #expect(JSONSyntax.tokens(in: "").isEmpty)
    }
}

@Suite("SQL 语法高亮")
struct SQLSyntaxTests {

    @Test("关键字大小写不敏感")
    func keywordsAreCaseInsensitive() {
        #expect(classified("SELECT 1", .sql).contains { $0 == (.keyword, "SELECT") })
        #expect(classified("select 1", .sql).contains { $0 == (.keyword, "select") })
        #expect(classified("Select 1", .sql).contains { $0 == (.keyword, "Select") })
    }

    @Test("表名与列名不是关键字")
    func identifiersAreNotKeywords() {
        let tokens = classified("SELECT id, name FROM users", .sql)
        #expect(tokens.contains { $0 == (.plain, "id") })
        #expect(tokens.contains { $0 == (.plain, "name") })
        #expect(tokens.contains { $0 == (.plain, "users") })
        #expect(tokens.filter { $0.0 == .keyword }.count == 2)  // SELECT / FROM
    }

    @Test("多词关键字逐个识别")
    func multiWordKeywords() {
        let tokens = classified("SELECT * FROM a LEFT JOIN b ON a.id = b.id", .sql)
        for word in ["SELECT", "FROM", "LEFT", "JOIN", "ON"] {
            #expect(tokens.contains { $0 == (.keyword, word) }, "\(word) 未被识别为关键字")
        }
    }

    @Test("字符串里的关键字不上色")
    func keywordsInsideStringsStayString() {
        let tokens = classified("SELECT 'select from where'", .sql)
        #expect(tokens.contains { $0 == (.string, "'select from where'") })
        #expect(tokens.filter { $0.0 == .keyword }.count == 1)  // 只有最外层那个 SELECT
    }

    @Test("SQL 的单引号转义是两个连续单引号")
    func doubledQuoteEscape() {
        // `'it''s'` 是一个字符串。按反斜杠转义处理的话会在 it' 处断开
        let tokens = classified("SELECT 'it''s ok'", .sql)
        #expect(tokens.contains { $0 == (.string, "'it''s ok'") })
    }

    @Test("行注释与块注释")
    func comments() {
        #expect(classified("SELECT 1 -- 说明", .sql).contains { $0 == (.comment, "-- 说明") })
        #expect(classified("SELECT /* 块 */ 1", .sql).contains { $0 == (.comment, "/* 块 */") })
        // 未闭合的块注释染到末尾
        #expect(classified("SELECT /* 没关", .sql).contains { $0 == (.comment, "/* 没关") })
    }

    @Test("注释里的关键字不上色")
    func keywordsInsideCommentsStayComment() {
        let tokens = classified("-- SELECT FROM\nSELECT 1", .sql)
        #expect(tokens.contains { $0 == (.comment, "-- SELECT FROM") })
        #expect(tokens.filter { $0.0 == .keyword }.count == 1)
    }

    @Test("被引号括起来的标识符与数字")
    func quotedIdentifiersAndNumbers() {
        #expect(classified(#"SELECT "select" FROM t"#, .sql).contains { $0 == (.key, #""select""#) })
        #expect(classified("SELECT `order` FROM t", .sql).contains { $0 == (.key, "`order`") })
        #expect(classified("LIMIT 10 OFFSET 20", .sql).contains { $0 == (.number, "10") })
        #expect(classified("LIMIT 10 OFFSET 20", .sql).contains { $0 == (.number, "20") })
    }

    @Test("标点与运算符")
    func punctuation() {
        let tokens = classified("SELECT a.id FROM a WHERE a.n >= 3", .sql)
        #expect(tokens.contains { $0 == (.punctuation, ".") })
        #expect(
            tokens.contains { $0 == (.punctuation, ">=") } || tokens.contains { $0 == (.punctuation, ">") })
    }

    @Test("空文本没有 token")
    func emptyTextHasNoTokens() {
        #expect(SQLSyntax.tokens(in: "").isEmpty)
    }
}

@Suite("语法高亮渲染")
@MainActor
struct SyntaxHighlighterTests {

    @Test("上色不改变文本内容")
    func highlightingPreservesText() {
        let source = #"{"a": [1, true, null]}"#
        let attributed = SyntaxHighlighter.attributed(source, language: .json)
        // 高亮只是加属性；字符必须一字不差，否则用户复制出来的东西会变
        #expect(String(attributed.characters) == source)
    }

    @Test("每个类别都有自己的颜色，且与正文色不同")
    func everyKindHasDistinctColor() {
        var seen = Set<String>()
        for kind in SyntaxTokenKind.allCases {
            let color = SyntaxHighlighter.color(for: kind)
            seen.insert(String(describing: color))
        }
        // 键 / 字符串 / 数字 / 字面量 / 关键字 / 注释 / 标点 / 正文，八类都不同色，
        // 否则「高亮」分不出结构
        #expect(seen.count == SyntaxTokenKind.allCases.count)
    }
}
