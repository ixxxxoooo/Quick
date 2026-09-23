// PluginTranslatorTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginTranslator

// MARK: - 语言探测

@Suite("语言探测")
struct LanguageDetectorTests {

    @Test("假名优先于汉字：含汉字的日文判成日语")
    func kanaBeatsKanji() {
        #expect(LanguageDetector.detect("これはテストです") == "ja")
        #expect(LanguageDetector.detect("日本語のテスト") == "ja")
    }

    @Test("韩文谚文、西里尔、阿拉伯、泰文")
    func otherScripts() {
        #expect(LanguageDetector.detect("안녕하세요") == "ko")
        #expect(LanguageDetector.detect("Привет мир") == "ru")
        #expect(LanguageDetector.detect("مرحبا") == "ar")
        #expect(LanguageDetector.detect("สวัสดี") == "th")
    }

    @Test("汉字判成简体中文，其余归英语")
    func kanjiAndLatin() {
        #expect(LanguageDetector.detect("今天天气很好") == "zh-Hans")
        #expect(LanguageDetector.detect("Hello world") == "en")
        #expect(LanguageDetector.detect("") == "en")
        #expect(LanguageDetector.detect("   ") == "en")
    }
}

// MARK: - 语言对取舍

@Suite("语言对取舍")
struct LanguageResolutionTests {

    @Test("源语言不是自动时原样返回")
    func explicitSourceWins() {
        let pair = LanguageResolution.effective(source: "fr", target: "en", detected: "en")
        #expect(pair.source == "fr")
        #expect(pair.target == "en")
    }

    @Test("自动检测时用探测结果")
    func autoUsesDetection() {
        let pair = LanguageResolution.effective(source: "auto", target: "zh-Hans", detected: "en")
        #expect(pair.source == "en")
        #expect(pair.target == "zh-Hans")
    }

    @Test("探测语言与目标相同时自动翻到另一种")
    func sameLanguageFlipsTarget() {
        let pair = LanguageResolution.effective(source: "auto", target: "zh-Hans", detected: "zh-Hans")
        #expect(pair.source == "zh-Hans")
        #expect(pair.target == "en")

        let pair2 = LanguageResolution.effective(source: "auto", target: "en", detected: "en")
        #expect(pair2.source == "en")
        #expect(pair2.target == "zh-Hans")
    }

    @Test("交换语言：显式源语言直接对调")
    func swapExplicit() {
        let swapped = LanguageResolution.swapped(
            source: "fr", target: "en", effective: EffectiveLanguages(source: "fr", target: "en"))
        #expect(swapped.source == "en")
        #expect(swapped.target == "fr")
    }

    @Test("交换语言：自动源语言用上次生效的语言对")
    func swapAutoUsesEffective() {
        let swapped = LanguageResolution.swapped(
            source: "auto", target: "zh-Hans",
            effective: EffectiveLanguages(source: "en", target: "zh-Hans"))
        #expect(swapped.source == "zh-Hans")
        #expect(swapped.target == "en")
    }
}

// MARK: - 词典解析

@Suite("词典解析")
struct DictionaryParserTests {

    @Test("英文词条：词头 / 音标 / 词性 / 释义 / 例句")
    func parsesEnglishEntry() {
        let raw =
            "apple | BrE ˈapl, AmE ˈæp(ə)l | noun (fruit) 苹果 píngguǒ; (tree) 苹果树 píngguǒ shù▸ the apple of sb's eye 掌上明珠"
        let entry = DictionaryParser.parse(raw: raw, query: "apple")
        #expect(entry.word == "apple")
        #expect(entry.phonetic.contains("BrE"))
        #expect(entry.senses.count == 1)
        #expect(entry.senses.first?.pos == "n.")
        #expect(entry.senses.first?.meaning.contains("苹果") == true)
        #expect(entry.examples.count == 1)
    }

    @Test("多义项按 ①② 切分")
    func splitsMultipleSenses() {
        let raw = "beautiful | BrE x, AmE y | adjective ① (attractive) 美丽的 ② (wonderful) 令人愉悦的"
        let entry = DictionaryParser.parse(raw: raw, query: "beautiful")
        #expect(entry.senses.count == 2)
        #expect(entry.senses.allSatisfy { $0.pos == "adj." })
        #expect(entry.senses[1].meaning.contains("令人愉悦"))
    }

    @Test("没有竖线分隔时退回整段释义")
    func fallsBackToWholeBody() {
        let raw = "苹果 píngguǒ 名 落叶乔木，叶子椭圆形。"
        let entry = DictionaryParser.parse(raw: raw, query: "苹果")
        #expect(entry.word == "苹果")
        #expect(entry.senses.count == 1)
        #expect(entry.senses.first?.meaning.contains("落叶乔木") == true)
    }

    @Test("空文本返回空词条")
    func emptyRaw() {
        #expect(DictionaryParser.parse(raw: "", query: "x").isEmpty)
        #expect(DictionaryParser.parse(raw: "   ", query: "x").isEmpty)
    }

    @Test("可复制文本包含词头与释义")
    func displayText() {
        let entry = DictionaryParser.parse(
            raw: "sync | BrE sɪŋk | noun = synchronization", query: "sync")
        #expect(entry.displayText.contains("sync"))
        #expect(entry.displayText.contains("synchronization"))
    }
}

// MARK: - 触发词

@Suite("触发词解析")
struct TranslatorQueryTests {

    @Test("翻译前缀")
    func translatePrefixes() {
        #expect(TranslatorQuery.intent(in: "翻译 你好") == .translate("你好"))
        #expect(TranslatorQuery.intent(in: "tr hello") == .translate("hello"))
        #expect(TranslatorQuery.intent(in: "translate hello") == .translate("hello"))
        #expect(TranslatorQuery.intent(in: "fy hello") == .translate("hello"))
    }

    @Test("词典前缀")
    func dictionaryPrefixes() {
        #expect(TranslatorQuery.intent(in: "词典 apple") == .dictionary("apple"))
        #expect(TranslatorQuery.intent(in: "dict apple") == .dictionary("apple"))
        #expect(TranslatorQuery.intent(in: "dictionary apple") == .dictionary("apple"))
        #expect(TranslatorQuery.intent(in: "查词 apple") == .dictionary("apple"))
    }

    @Test("前缀大小写不敏感，正文原样保留")
    func caseInsensitivePrefix() {
        #expect(TranslatorQuery.intent(in: "TR Hello") == .translate("Hello"))
        #expect(TranslatorQuery.intent(in: "Dict Apple") == .dictionary("Apple"))
    }

    @Test("只打触发词返回 nil")
    func bareTrigger() {
        #expect(TranslatorQuery.intent(in: "tr ") == nil)
        #expect(TranslatorQuery.intent(in: "词典 ") == nil)
        #expect(TranslatorQuery.intent(in: "dict") == nil)
        #expect(TranslatorQuery.intent(in: "hello") == nil)
        #expect(TranslatorQuery.intent(in: "") == nil)
    }

    @Test("text(in:) 只取翻译意图")
    func textHelper() {
        #expect(TranslatorQuery.text(in: "翻译 你好") == "你好")
        #expect(TranslatorQuery.text(in: "词典 apple") == nil)
    }
}

// MARK: - 插件契约

@Suite("翻译插件契约")
@MainActor
struct TranslatorPluginTests {

    private func makePlugin() throws -> TranslatorPlugin {
        let database = try SQLiteDatabase()
        try database.migrate([.corePluginData])
        return TranslatorPlugin(
            storage: PluginStorage(pluginID: TranslatorPlugin.id, database: database))
    }

    @Test("id 是约定的字面量且为 kebab-case")
    func identifierConvention() {
        #expect(TranslatorPlugin.id == "translator")
    }

    @Test("名称、图标与触发词非空")
    func displayMetadataIsPresent() {
        #expect(!TranslatorPlugin.name.isEmpty)
        #expect(!TranslatorPlugin.icon.isEmpty)
        #expect(!TranslatorPlugin.triggerWords.isEmpty)
    }

    @Test("无关查询不返回结果")
    func unrelatedQueryYieldsNothing() async throws {
        let plugin = try makePlugin()
        #expect(await plugin.searchItems(query: "definitely-unrelated").isEmpty)
        #expect(await plugin.searchItems(query: "").isEmpty)
    }

    @Test("查词命中系统词典时返回词典条目")
    func dictionaryLookupReturnsItem() async throws {
        let plugin = try makePlugin()
        let items = await plugin.searchItems(query: "dict apple")
        // 系统词典在绝大多数机器上都有；命中时校验结构，没有也不强求
        if let item = items.first {
            #expect(item.pluginID == TranslatorPlugin.id)
            #expect(item.id == "translator.dict")
            #expect(!item.title.isEmpty)
        }
    }
}
