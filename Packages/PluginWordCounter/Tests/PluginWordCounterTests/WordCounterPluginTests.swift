// WordCounterPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginWordCounter

@Suite("字数统计逻辑")
struct WordCounterLogicTests {

    @Test("空文本全部为零，但阅读时长下限是 1 分钟")
    func emptyText() {
        // 阅读时长用 max(1, ...) 兜底，空文本也显示「约 1 分钟」，这是原有行为
        let stats = WordCounterLogic.stats(for: "")
        #expect(stats.characterCount == 0)
        #expect(stats.characterCountNoSpaces == 0)
        #expect(stats.wordCount == 0)
        #expect(stats.lineCount == 0)
        #expect(stats.byteCount == 0)
        #expect(stats.chineseCount == 0)
        #expect(stats.englishCount == 0)
        #expect(stats.digitCount == 0)
        #expect(stats.punctuationCount == 0)
        #expect(stats.readingMinutes == 1)
        #expect(stats.readingTime == "约 1 分钟")
    }

    @Test("单个单词")
    func singleWord() {
        let stats = WordCounterLogic.stats(for: "hello")
        #expect(stats.characterCount == 5)
        #expect(stats.characterCountNoSpaces == 5)
        #expect(stats.wordCount == 1)
        #expect(stats.lineCount == 1)
        #expect(stats.byteCount == 5)
        #expect(stats.englishCount == 5)
        #expect(stats.chineseCount == 0)
    }

    @Test("空格分隔的多个单词")
    func multipleWords() {
        let stats = WordCounterLogic.stats(for: "hello world")
        #expect(stats.characterCount == 11)
        #expect(stats.characterCountNoSpaces == 10)
        #expect(stats.wordCount == 2)
        #expect(stats.lineCount == 1)
    }

    @Test("换行计入行数，也把单词切开")
    func newlinesSplitLinesAndWords() {
        let stats = WordCounterLogic.stats(for: "a\nb")
        #expect(stats.characterCount == 3)
        #expect(stats.characterCountNoSpaces == 2)  // 换行属于空白，被过滤
        #expect(stats.wordCount == 2)
        #expect(stats.lineCount == 2)
        #expect(stats.byteCount == 3)
    }

    @Test("空行计入行数，但不产生单词")
    func blankLinesCountAsLines() {
        let stats = WordCounterLogic.stats(for: "a\n\nb")
        #expect(stats.lineCount == 3)
        #expect(stats.wordCount == 2)
        #expect(stats.characterCount == 4)
        #expect(stats.characterCountNoSpaces == 2)
    }

    @Test("末尾换行会多出一行")
    func trailingNewlineAddsALine() {
        let stats = WordCounterLogic.stats(for: "a\n")
        #expect(stats.lineCount == 2)
        #expect(stats.wordCount == 1)
        #expect(stats.characterCount == 2)
    }

    @Test("纯空白：有字符、有行，但没有单词")
    func whitespaceOnly() {
        let stats = WordCounterLogic.stats(for: "   ")
        #expect(stats.characterCount == 3)
        #expect(stats.characterCountNoSpaces == 0)
        #expect(stats.wordCount == 0)
        #expect(stats.lineCount == 1)
    }

    @Test("中文文本按字符计数，字节数按 UTF-8")
    func chineseText() {
        let stats = WordCounterLogic.stats(for: "你好世界")
        #expect(stats.characterCount == 4)
        #expect(stats.chineseCount == 4)
        #expect(stats.englishCount == 0)
        #expect(stats.wordCount == 1)
        #expect(stats.byteCount == 12)
    }

    @Test("中英数字混排的各语言计数")
    func mixedText() {
        let stats = WordCounterLogic.stats(for: "你好 world 123!")
        #expect(stats.characterCount == 13)
        #expect(stats.characterCountNoSpaces == 11)
        #expect(stats.wordCount == 3)  // 「123!」被算作一个单词
        #expect(stats.chineseCount == 2)
        #expect(stats.englishCount == 5)
        #expect(stats.digitCount == 3)
        #expect(stats.punctuationCount == 1)
        #expect(stats.byteCount == 17)
    }

    @Test("标点不进英文或数字计数")
    func punctuationOnlyCountsAsPunctuation() {
        let stats = WordCounterLogic.stats(for: "hello, world!")
        #expect(stats.englishCount == 10)
        #expect(stats.punctuationCount == 2)
        #expect(stats.digitCount == 0)
        #expect(stats.wordCount == 2)
    }

    @Test("字母和数字分开计数")
    func lettersAndDigitsAreSeparate() {
        let stats = WordCounterLogic.stats(for: "abc123")
        #expect(stats.englishCount == 3)
        #expect(stats.digitCount == 3)
        #expect(stats.characterCount == 6)
        #expect(stats.wordCount == 1)
    }

    @Test("emoji 算 1 个字符、4 个字节")
    func emojiCountsAsOneCharacter() {
        let stats = WordCounterLogic.stats(for: "👍")
        #expect(stats.characterCount == 1)
        #expect(stats.byteCount == 4)
        #expect(stats.chineseCount == 0)
        #expect(stats.englishCount == 0)
        #expect(stats.punctuationCount == 0)
    }

    @Test("只有标点的文本仍被算作一个单词")
    func punctuationOnlyStillCountsAsAWord() {
        // 单词数只看空白边界，不看内容 —— 这是原有行为，不是本次引入的
        let stats = WordCounterLogic.stats(for: "!!!")
        #expect(stats.wordCount == 1)
        #expect(stats.punctuationCount == 3)
    }

    @Test("阅读时长按每 500 字一分钟，向下取整，下限 1 分钟")
    func readingTimeBoundaries() {
        func minutes(_ count: Int) -> Int {
            WordCounterLogic.stats(for: String(repeating: "a", count: count)).readingMinutes
        }
        #expect(minutes(0) == 1)
        #expect(minutes(499) == 1)
        #expect(minutes(500) == 1)
        #expect(minutes(999) == 1)
        #expect(minutes(1000) == 2)
        #expect(minutes(1500) == 3)
    }
}

@Suite("字数统计插件契约")
@MainActor
struct WordCounterPluginTests {

    @Test("插件 id 是 kebab-case 且与约定一致")
    func identifierIsKebabCase() {
        let id = WordCounterPlugin.id
        #expect(id == "word-counter")
        #expect(id == id.lowercased())
        #expect(id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        #expect(!id.hasPrefix("-") && !id.hasSuffix("-"))
    }

    @Test("名称、图标、触发词都不为空")
    func metadataIsPresent() {
        #expect(!WordCounterPlugin.name.isEmpty)
        #expect(!WordCounterPlugin.icon.isEmpty)
        #expect(!WordCounterPlugin.triggerWords.isEmpty)
        #expect(WordCounterPlugin.icon == "textformat.123")
    }

    @Test("命中触发词时只返回一条结果")
    func triggerReturnsExactlyOneItem() async {
        let plugin = WordCounterPlugin()
        let results = await plugin.searchItems(query: "字数")

        #expect(results.count == 1)
        #expect(results.first?.pluginID == WordCounterPlugin.id)
        #expect(results.first?.icon == WordCounterPlugin.icon)
    }

    @Test("不命中触发词时返回空")
    func unrelatedQueryReturnsNothing() async {
        let plugin = WordCounterPlugin()
        #expect(await plugin.searchItems(query: "zzzz").isEmpty)
    }
}
