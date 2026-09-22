// URLCodecPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginURLCodec

@Suite("URL 编解码逻辑")
struct URLCodecLogicTests {

    // MARK: - 编码

    @Test("非 ASCII 按 UTF-8 逐字节编码")
    func encodesNonASCII() {
        #expect(URLCodecLogic.encode("中") == "%E4%B8%AD")
    }

    @Test("空格编成 %20 而不是加号")
    func encodesSpaceAsPercentTwenty() {
        #expect(URLCodecLogic.encode("a b") == "a%20b")
    }

    @Test("查询串分隔符保持原样，方便粘贴进已有查询串")
    func keepsQuerySeparators() {
        #expect(URLCodecLogic.encode("a b&c=d") == "a%20b&c=d")
    }

    @Test("空输入编码后仍是空串")
    func encodesEmptyString() {
        #expect(URLCodecLogic.encode("") == "")
    }

    // MARK: - 解码

    @Test("百分号序列按 UTF-8 还原")
    func decodesPercentSequence() throws {
        #expect(try URLCodecLogic.decode("%E4%B8%AD") == "中")
    }

    @Test("解码不把加号当成空格")
    func decodeKeepsPlus() throws {
        #expect(try URLCodecLogic.decode("a+b") == "a+b")
    }

    @Test("空输入解码后仍是空串")
    func decodesEmptyString() throws {
        #expect(try URLCodecLogic.decode("") == "")
    }

    /// `%E4%B8` 每个百分号序列本身合法，但拼出来不是合法 UTF-8，
    /// 必须和 `%ZZ` 一样报错 —— 否则会解出半个字符。
    @Test("非法百分号序列报错而不是回退原文", arguments: ["%ZZ", "abc%", "100%", "%2", "%E4%B8"])
    func malformedInputThrows(_ input: String) {
        #expect(throws: URLCodecLogic.DecodeError.malformedPercentSequence) {
            try URLCodecLogic.decode(input)
        }
    }

    // MARK: - 往返

    @Test("编码后再解码回到原文", arguments: ["中", "a b&c=d", "https://example.com/路径?q=值", ""])
    func roundTrip(_ original: String) throws {
        #expect(try URLCodecLogic.decode(URLCodecLogic.encode(original)) == original)
    }
}

@Suite("URL 编解码插件契约")
@MainActor
struct URLCodecPluginTests {

    /// 插件 id 必须是 kebab-case
    ///
    /// 它同时是事件路由和设置存储的主键，混入下划线或大写会让
    /// 「按 id 查配置」的调用点开始出错。
    private func isKebabCase(_ value: String) -> Bool {
        !value.isEmpty
            && !value.contains("_")
            && value.allSatisfy { $0.isNumber || $0 == "-" || ("a"..."z").contains($0) }
    }

    @Test("id 是 kebab-case 且与约定一致")
    func identifierConvention() {
        #expect(URLCodecPlugin.id == "url-codec")
        #expect(isKebabCase(URLCodecPlugin.id))
    }

    @Test("名称、图标、触发词都不为空")
    func metadataIsPresent() {
        #expect(!URLCodecPlugin.name.isEmpty)
        #expect(!URLCodecPlugin.icon.isEmpty)
        #expect(!URLCodecPlugin.triggerWords.isEmpty)
    }

    @Test("任一触发词都能唤醒插件，且只返回一个入口", arguments: ["url", "编码", "解码", "URL 编解码"])
    func searchItemsMatchTrigger(_ trigger: String) async {
        let items = await URLCodecPlugin().searchItems(query: trigger)
        #expect(items.count == 1)
        #expect(items.first?.id == "url-codec.open")
        #expect(items.first?.pluginID == URLCodecPlugin.id)
    }

    @Test("无关查询不返回结果")
    func unrelatedQueryReturnsNothing() async {
        let items = await URLCodecPlugin().searchItems(query: "天气")
        #expect(items.isEmpty)
    }
}
