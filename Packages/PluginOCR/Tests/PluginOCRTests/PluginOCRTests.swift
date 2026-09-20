// PluginOCRTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginOCR

// MARK: - 纯逻辑

@Suite("OCR 文本拼装")
struct OCRTextTests {

    @Test("多条观测按顺序用换行连接")
    func joinsObservationsInOrder() {
        #expect(OCRText.joined(["第一行", "second", "第三"]) == "第一行\nsecond\n第三")
    }

    @Test("单条观测原样返回")
    func singleObservationIsUnchanged() {
        #expect(OCRText.joined(["hello"]) == "hello")
    }

    @Test("没有观测时返回空串")
    func noObservationYieldsEmpty() {
        #expect(OCRText.joined([]) == "")
    }

    @Test("空观测不过滤，只留下额外的空行")
    func emptyObservationsKeepTheirNewlines() {
        #expect(OCRText.joined(["a", "", "b"]) == "a\n\nb")
        #expect(OCRText.joined([""]) == "")
        #expect(OCRText.joined(["", ""]) == "\n")
    }

    @Test("换行与制表符不被改写")
    func existingNewlinesArePreserved() {
        #expect(OCRText.joined(["a\nb", "c"]) == "a\nb\nc")
    }
}

@Suite("OCR 触发词匹配")
struct OCRQueryTests {

    @Test("触发词列表非空且无空项")
    func triggersAreWellFormed() {
        #expect(!OCRQuery.triggers.isEmpty)
        #expect(OCRQuery.triggers.allSatisfy { !$0.isEmpty })
    }

    @Test("精确与大小写不同的拉丁触发词都能命中")
    func latinTriggersAreCaseInsensitive() {
        #expect(OCRQuery.isTriggered(by: "ocr"))
        #expect(OCRQuery.isTriggered(by: "OCR"))
        #expect(OCRQuery.isTriggered(by: "Ocr"))
    }

    @Test("中文触发词按包含匹配，带上下文也能命中")
    func chineseTriggersMatchInsideSentence() {
        #expect(OCRQuery.isTriggered(by: "识别"))
        #expect(OCRQuery.isTriggered(by: "文字识别"))
        #expect(OCRQuery.isTriggered(by: "截图识别"))
        #expect(OCRQuery.isTriggered(by: "帮我识别这段文字"))
        // 「无法识别」不是请 OCR，但包含「识别」——现状就是会命中
        #expect(OCRQuery.isTriggered(by: "无法识别"))
    }

    @Test("空查询与无关查询都不命中")
    func unrelatedQueriesDoNotMatch() {
        #expect(!OCRQuery.isTriggered(by: ""))
        #expect(!OCRQuery.isTriggered(by: "banana"))
        #expect(!OCRQuery.isTriggered(by: "翻译 hello"))
    }

    @Test("拉丁触发词是子串匹配，因此 ocr 会藏进无关单词里")
    func latinTriggerMatchesSubstring() {
        // microcre 的第 5~7 个字符正是 ocr —— 现状行为，已记录在案
        #expect(OCRQuery.isTriggered(by: "microcre"))
    }
}

// MARK: - 插件契约

@Suite("文字识别插件契约")
@MainActor
struct OCRPluginTests {

    @Test("id 是约定的字面量且为 kebab-case")
    func identifierConvention() {
        #expect(OCRPlugin.id == "ocr")
        #expect(
            OCRPlugin.id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" },
            "id 是事件路由与设置存储的主键，必须是 kebab-case，实际为 \(OCRPlugin.id)"
        )
    }

    @Test("名称与图标非空")
    func displayMetadataIsPresent() {
        #expect(!OCRPlugin.name.isEmpty)
        #expect(!OCRPlugin.icon.isEmpty)
        #expect(!OCRPlugin.triggerWords.isEmpty)
    }

    @Test("触发词只有一份，插件声明与匹配逻辑共用")
    func triggerWordsAreSharedWithMatcher() {
        #expect(OCRPlugin.triggerWords == OCRQuery.triggers)
    }

    @Test("触发词能命中截图识别入口")
    func triggerWordYieldsTheCaptureEntry() async {
        let plugin = OCRPlugin()
        let items: [SearchableItem] = await plugin.searchItems(query: "ocr")

        #expect(items.count == 1, "输入触发词应只给出一个入口，实际 \(items.count) 个")
        #expect(items.first?.id == "ocr.capture")
        #expect(items.first?.pluginID == OCRPlugin.id)
    }

    @Test("无关查询不返回结果")
    func unrelatedQueryYieldsNothing() async {
        let plugin = OCRPlugin()
        #expect(await plugin.searchItems(query: "definitely-unrelated").isEmpty)
        #expect(await plugin.searchItems(query: "").isEmpty)
    }

    @Test("生命周期方法可重复调用")
    func lifecycleIsIdempotent() {
        let plugin = OCRPlugin()
        plugin.activate()
        plugin.activate()
        plugin.deactivate()
        plugin.deactivate()
        #expect(plugin.isEnabled)
    }
}
