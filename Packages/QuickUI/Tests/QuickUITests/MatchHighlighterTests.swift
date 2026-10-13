// MatchHighlighterTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import QuickUI

@Suite("结果标题命中高亮")
struct MatchHighlighterTests {

    /// 把区间还原成命中的文本，断言更直观
    private func hits(_ title: String, _ query: String) -> [String] {
        MatchHighlighter.ranges(in: title, query: query).map { String(title[$0]) }
    }

    @Test("子串命中不区分大小写")
    func caseInsensitiveSubstring() {
        #expect(hits("Visual Studio Code", "studio") == ["Studio"])
    }

    @Test("多个词各自命中")
    func multipleTokens() {
        #expect(hits("Visual Studio Code", "code vis") == ["Vis", "Code"])
    }

    @Test("缩写按顺序命中字符")
    func abbreviationSubsequence() {
        #expect(hits("Visual Studio Code", "vsc") == ["V", "S", "C"])
    }

    @Test("缩写优先落在词首，而不是词中间的同名字母")
    func abbreviationPrefersWordStart() {
        // "Visual" 里的 s 在前，但缩写 vsc 指的是 Studio 的 S
        let title = "Visual Studio Code"
        let ranges = MatchHighlighter.ranges(in: title, query: "vsc")
        #expect(ranges.map { title.distance(from: title.startIndex, to: $0.lowerBound) } == [0, 7, 14])
    }

    @Test("缩写顺序不对则不命中")
    func abbreviationOutOfOrder() {
        #expect(hits("Code", "edoc").isEmpty)
    }

    @Test("相邻与重叠的命中合并")
    func adjacentMerged() {
        #expect(hits("abcdef", "abc cde") == ["abcde"])
    }

    @Test("空查询与空标题不命中")
    func emptyInputs() {
        #expect(hits("Safari", "").isEmpty)
        #expect(hits("Safari", "   ").isEmpty)
        #expect(hits("", "a").isEmpty)
    }

    @Test("不区分音标")
    func diacriticInsensitive() {
        #expect(hits("Café", "cafe") == ["Café"])
    }

    @Test("中文子串命中")
    func chineseSubstring() {
        #expect(hits("系统设置", "设置") == ["设置"])
    }

    @Test("attributed 只给命中部分加粗")
    func attributedEmphasisOnlyOnHits() {
        let text = MatchHighlighter.attributed(title: "Safari", query: "fa")
        let emphasised = text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
        #expect(emphasised.count == 1)
        #expect(String(text[emphasised[0].range].characters) == "fa")
    }

    @Test("无命中时 attributed 不带强调")
    func attributedNoHits() {
        let text = MatchHighlighter.attributed(title: "Safari", query: "zzz")
        #expect(text.runs.allSatisfy { $0.inlinePresentationIntent == nil })
    }
}
