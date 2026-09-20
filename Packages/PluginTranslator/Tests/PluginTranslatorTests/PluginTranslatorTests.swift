// PluginTranslatorTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginTranslator

// MARK: - 纯逻辑

@Suite("翻译方向")
struct TranslationDirectionTests {

    @Test("中文（简体与繁体）译成英文")
    func chineseGoesToEnglish() {
        #expect(TranslationDirection.direction(forSourceLanguage: "zh-Hans") == .toEnglish)
        #expect(TranslationDirection.direction(forSourceLanguage: "zh-Hant") == .toEnglish)
    }

    @Test("非中文与识别不出语言都译成中文")
    func everythingElseGoesToChinese() {
        #expect(TranslationDirection.direction(forSourceLanguage: "en") == .toChinese)
        #expect(TranslationDirection.direction(forSourceLanguage: "ja") == .toChinese)
        #expect(TranslationDirection.direction(forSourceLanguage: "ko") == .toChinese)
        #expect(TranslationDirection.direction(forSourceLanguage: nil) == .toChinese)
        #expect(TranslationDirection.direction(forSourceLanguage: "") == .toChinese)
    }

    @Test("目标语言 tag 与展示名")
    func targetMetadataMatchesDirection() {
        #expect(TranslationDirection.toEnglish.targetCode == "en")
        #expect(TranslationDirection.toEnglish.targetDisplayName == "英文")
        #expect(TranslationDirection.toChinese.targetCode == "zh-Hans")
        #expect(TranslationDirection.toChinese.targetDisplayName == "中文")
    }
}

@Suite("内置词典")
struct TranslationDictionaryTests {

    @Test("词表内中译英")
    func chineseEntriesTranslateToEnglish() {
        #expect(TranslationDictionary.lookup("你好") == "Hello")
        #expect(TranslationDictionary.lookup("谢谢") == "Thank you")
        #expect(TranslationDictionary.lookup("再见") == "Goodbye")
    }

    @Test("词表内英译中且大小写不敏感")
    func englishEntriesAreCaseInsensitive() {
        #expect(TranslationDictionary.lookup("hello") == "你好")
        #expect(TranslationDictionary.lookup("Hello") == "你好")
        #expect(TranslationDictionary.lookup("HELLO") == "你好")
        #expect(TranslationDictionary.lookup("thank you") == "谢谢")
        #expect(TranslationDictionary.lookup("Thank You") == "谢谢")
    }

    @Test("词表外查不到，返回 nil")
    func unknownTextIsNotInTheTable() {
        #expect(TranslationDictionary.lookup("苹果") == nil)
        #expect(TranslationDictionary.lookup("") == nil)
        #expect(TranslationDictionary.lookup("hell") == nil)
        #expect(TranslationDictionary.lookup("你好 ") == nil, "词典是精确匹配，不做首尾去空白")
    }

    @Test("兜底文案带目标语言标注")
    func fallbackIsLabelledWithTargetLanguage() {
        #expect(TranslationDictionary.fallback("苹果", direction: .toChinese) == "[中文翻译] 苹果")
        #expect(TranslationDictionary.fallback("pear", direction: .toEnglish) == "[英文翻译] pear")
        #expect(TranslationDictionary.fallback("", direction: .toChinese) == "[中文翻译] ")
    }

    @Test("先查词，查不到才兜底")
    func translatePrefersTheTable() {
        #expect(TranslationDictionary.translate("你好", direction: .toEnglish) == "Hello")
        #expect(TranslationDictionary.translate("苹果", direction: .toChinese) == "[中文翻译] 苹果")
        // 方向只影响兜底文案，不影响查词结果
        #expect(TranslationDictionary.translate("你好", direction: .toChinese) == "Hello")
    }

    @Test("词表的键全部是小写，否则大小写不敏感就失效了")
    func keysAreLowercased() {
        #expect(TranslationDictionary.entries.keys.allSatisfy { $0 == $0.lowercased() })
        #expect(!TranslationDictionary.entries.isEmpty)
    }
}

@Suite("翻译触发词解析")
struct TranslatorQueryTests {

    @Test("四个前缀都能剥掉")
    func everyPrefixIsStripped() {
        #expect(TranslatorQuery.text(in: "翻译 你好") == "你好")
        #expect(TranslatorQuery.text(in: "tr hello") == "hello")
        #expect(TranslatorQuery.text(in: "translate hello") == "hello")
        #expect(TranslatorQuery.text(in: "fy hello") == "hello")
    }

    @Test("触发词大小写不敏感，正文大小写原样保留")
    func prefixIsCaseInsensitiveButBodyIsNot() {
        #expect(TranslatorQuery.text(in: "TR Hello") == "Hello")
        #expect(TranslatorQuery.text(in: "Translate HELLO") == "HELLO")
    }

    @Test("只打触发词（正文为空）返回 nil")
    func bareTriggerYieldsNothing() {
        #expect(TranslatorQuery.text(in: "tr ") == nil)
        #expect(TranslatorQuery.text(in: "翻译 ") == nil)
        #expect(TranslatorQuery.text(in: "tr") == nil)
        #expect(TranslatorQuery.text(in: "translate") == nil)
    }

    @Test("前缀必须带空格，中文触发词也不能省")
    func prefixNeedsTrailingSpace() {
        #expect(TranslatorQuery.text(in: "翻译你好") == nil)
        #expect(TranslatorQuery.text(in: " 翻译 你好") == nil, "前导空白不匹配，触发词必须出现在开头")
        #expect(TranslatorQuery.text(in: "") == nil)
        #expect(TranslatorQuery.text(in: "hello") == nil)
    }

    @Test("translate 不会被更短的 tr 抢走")
    func longerPrefixWinsByBeingTheOnlyMatch() {
        #expect(TranslatorQuery.text(in: "translate hello") == "hello")
        #expect(TranslatorQuery.text(in: "fy 你好") == "你好")
    }

    @Test("触发前缀非空且无重复")
    func prefixesAreWellFormed() {
        #expect(!TranslatorQuery.prefixes.isEmpty)
        #expect(TranslatorQuery.prefixes.allSatisfy { !$0.isEmpty })
        #expect(Set(TranslatorQuery.prefixes).count == TranslatorQuery.prefixes.count)
    }
}

// MARK: - 插件契约

@Suite("翻译插件契约")
@MainActor
struct TranslatorPluginTests {

    @Test("id 是约定的字面量且为 kebab-case")
    func identifierConvention() {
        #expect(TranslatorPlugin.id == "translator")
        #expect(
            TranslatorPlugin.id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" },
            "id 是事件路由与设置存储的主键，必须是 kebab-case，实际为 \(TranslatorPlugin.id)"
        )
    }

    @Test("名称、图标与触发词非空")
    func displayMetadataIsPresent() {
        #expect(!TranslatorPlugin.name.isEmpty)
        #expect(!TranslatorPlugin.icon.isEmpty)
        #expect(!TranslatorPlugin.triggerWords.isEmpty)
    }

    @Test("触发词能翻译出词典里的词")
    func triggerWordYieldsTranslation() async {
        let plugin = TranslatorPlugin()
        let items: [SearchableItem] = await plugin.searchItems(query: "tr hello")

        #expect(items.count == 1, "一个查询只给一条译文，实际 \(items.count) 条")
        #expect(items.first?.title == "你好")
        #expect(items.first?.pluginID == TranslatorPlugin.id)
        #expect(items.first?.id == "translator.result")
    }

    @Test("中文触发词同样可用")
    func chineseTriggerAlsoWorks() async {
        let plugin = TranslatorPlugin()
        let items = await plugin.searchItems(query: "翻译 谢谢")

        #expect(items.first?.title == "Thank you")
        #expect(items.first?.pluginID == TranslatorPlugin.id)
    }

    @Test("无关查询与空查询不返回结果")
    func unrelatedQueryYieldsNothing() async {
        let plugin = TranslatorPlugin()
        #expect(await plugin.searchItems(query: "definitely-unrelated").isEmpty)
        #expect(await plugin.searchItems(query: "").isEmpty)
    }

    @Test("只打触发词不返回结果")
    func bareTriggerYieldsNothing() async {
        let plugin = TranslatorPlugin()
        #expect(await plugin.searchItems(query: "tr").isEmpty)
        #expect(await plugin.searchItems(query: "translation").isEmpty)
    }
}
