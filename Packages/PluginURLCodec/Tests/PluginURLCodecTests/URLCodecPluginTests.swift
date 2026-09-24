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

    // MARK: - 空格编成加号

    @Test("表单模式下空格编成 + 且能解回来")
    func spacesAsPluses() throws {
        let options = URLCodecLogic.Options(encodesSpacesAsPluses: true)
        #expect(URLCodecLogic.encode("a b", options: options) == "a+b")
        #expect(try URLCodecLogic.decode("a+b", options: options) == "a b")
        // 默认模式不变：%20 是标准，+ 原样保留
        #expect(URLCodecLogic.encode("a b") == "a%20b")
        #expect(try URLCodecLogic.decode("a+b") == "a+b")
    }

    // MARK: - 完整 URL 模式

    @Test("完整 URL 模式保留协议与路径分隔符")
    func fullURLKeepsStructure() {
        let options = URLCodecLogic.Options(encodesFullURL: true)
        let encoded = URLCodecLogic.encode("https://example.com/路径?q=值", options: options)
        #expect(encoded.hasPrefix("https://example.com/"))
        #expect(encoded.contains("%E8%B7%AF%E5%BE%84"))
    }

    @Test("默认模式仍会编码冒号等结构字符")
    func defaultModeEncodesStructure() {
        #expect(URLCodecLogic.encode("https://example.com").contains("%3A"))
    }

    @Test("完整 URL 模式往返一致")
    func fullURLRoundTrip() throws {
        let options = URLCodecLogic.Options(encodesFullURL: true)
        let original = "https://example.com/路径?q=值&p=2"
        #expect(try URLCodecLogic.decode(URLCodecLogic.encode(original, options: options), options: options) == original)
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

    /// 入口由静态命令承载，不再由搜索现算 —— 原来这条测试问的是 `searchItems` 的返回，
    /// 那个遗留 API 已删除（见 docs/refactor-plan.md Phase 0）。
    @Test("编码与解码各有一条命令，且功能命令带插件前缀")
    func commandsCoverBothDirections() {
        let commands = URLCodecPlugin.commands
        let ids = commands.map(\.id)

        #expect(ids.contains("url-codec.encode"))
        #expect(ids.contains("url-codec.decode"))
        let functionIDs = commands.filter { !$0.id.hasPrefix("plugin.open.") }.map(\.id)
        #expect(functionIDs.allSatisfy { $0.hasPrefix("url-codec.") })
        #expect(commands.allSatisfy { $0.pluginID == URLCodecPlugin.id })
    }

    /// 通用词归 Base64 插件所有，URL 插件只能用带限定的触发词 ——
    /// 否则两套编解码器会在同一条查询上撞车。这条约束现在体现在触发词上。
    @Test("通用词「编码 / 解码」不在本插件的触发词里", arguments: ["编码", "解码", "encode", "decode"])
    func genericCodecWordsAreNotTriggers(_ word: String) {
        #expect(!word.matchesAnyTrigger(URLCodecPlugin.triggerWords))
    }

    @Test("插件不参与按查询现算")
    func doesNotTakePartInDynamicSearch() async {
        let plugin = URLCodecPlugin()

        #expect(!plugin.accepts(query: "url编码"))
        #expect(await plugin.dynamicSearch(query: "天气").isEmpty)
    }
}
