// SmartPreviewPanelTextTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import QuickUI

@Suite("智能预览：面板展示文本")
struct SmartPreviewPanelTextTests {

    @Test("一行能说完的预览不出卡，多行信息的才出卡")
    func richDetailSplit() {
        #expect(!SmartPreview.url(url: "https://a.com", domain: "a.com").hasRichDetail)
        #expect(!SmartPreview.math(expr: "1+1", result: "2").hasRichDetail)
        #expect(!SmartPreview.email(email: "a@b.c").hasRichDetail)
        #expect(!SmartPreview.plainText(summary: "x", charCount: 1).hasRichDetail)
        #expect(SmartPreview.color(hex: "#FF0000", rgb: "rgb(255,0,0)").hasRichDetail)
        #expect(SmartPreview.filePath(path: "/tmp", exists: true, isDirectory: true).hasRichDetail)
        #expect(SmartPreview.json(summary: "对象", lineCount: 3).hasRichDetail)
    }

    @Test("主标题直接给答案")
    func headline() {
        #expect(SmartPreview.math(expr: "1+2*3", result: "7").headline == "7")
        #expect(SmartPreview.url(url: "https://a.com/x", domain: "a.com").headline == "a.com")
        #expect(SmartPreview.filePath(path: "/tmp/a.txt", exists: true, isDirectory: false).headline == "a.txt")
        #expect(SmartPreview.json(summary: "对象", lineCount: 3).headline == "对象 · 3 行")
    }

    @Test("副标题：算式给原式，颜色给 RGB，没得补充就是 nil")
    func subheadline() {
        #expect(SmartPreview.math(expr: "1+2*3", result: "7").subheadline == "1+2*3")
        #expect(SmartPreview.color(hex: "#F00", rgb: "rgb(255,0,0)").subheadline == "rgb(255,0,0)")
        #expect(SmartPreview.email(email: "a@b.c").subheadline == nil)
    }

    @Test("复制文本：颜色只复制色值（不是颜色工具），翻译无结果时回落原文")
    func copyText() {
        #expect(SmartPreview.color(hex: "#FF5500", rgb: "rgb(255,85,0)").copyText(sourceText: "x") == "#FF5500")
        #expect(SmartPreview.math(expr: "1+1", result: "2").copyText(sourceText: "1+1") == "2")
        #expect(
            SmartPreview.translation(source: "hi", detectedLang: "en").copyText(sourceText: "hi") == "hi")
        #expect(SmartPreview.base64(decoded: "hello").copyText(sourceText: "aGVsbG8=") == "hello")
        #expect(SmartPreview.json(summary: "对象", lineCount: 1).copyText(sourceText: "{}") == "{}")
    }
}
