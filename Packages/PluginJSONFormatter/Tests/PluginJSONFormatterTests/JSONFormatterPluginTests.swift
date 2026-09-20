// JSONFormatterPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing
@testable import PluginJSONFormatter

@Suite("JSON 格式化逻辑")
struct JSONFormatterLogicTests {

    /// 缩进是视图唯一暴露的可调项，换行与每层空格数得对得上
    @Test("美化输出按 2 空格缩进换行")
    func prettyPrintIndentation() throws {
        let result = try JSONFormatterLogic.prettyPrint(#"{"b":1,"a":[1,2]}"#, indent: 2)
        #expect(result.text.contains("\n  \"a\" : ["))
        #expect(result.text.contains("\n  \"b\" : 1"))
        // 根字典 1 + 叶子 1 + 数组 1 + 两个元素 2
        #expect(result.nodeCount == 5)
    }

    @Test("缩进 4 时每层四个空格")
    func prettyPrintFourSpaceIndent() throws {
        let result = try JSONFormatterLogic.prettyPrint(#"{"b":1,"a":[1,2]}"#, indent: 4)
        #expect(result.text.contains("\n    \"a\" : ["))
        #expect(!result.text.contains("\n  \"a\" : ["))
    }

    @Test("压缩移除所有非必要空白")
    func minifyStripsWhitespace() throws {
        let compact = try JSONFormatterLogic.minify("{\n  \"a\" : 1,\n  \"b\" : 2\n}")
        #expect(compact == #"{"a":1,"b":2}"#)
    }

    /// 键序必须是确定的，否则同一份 JSON 每次输出都不同，用户会以为工具坏了
    @Test("两种输出都按键名排序")
    func outputSortsKeys() throws {
        let pretty = try JSONFormatterLogic.prettyPrint(#"{"z":1,"a":2}"#, indent: 2)
        let minified = try JSONFormatterLogic.minify(#"{"z":1,"a":2}"#)
        #expect(pretty.text.range(of: "\"a\"")!.lowerBound < pretty.text.range(of: "\"z\"")!.lowerBound)
        #expect(minified == #"{"a":2,"z":1}"#)
    }

    /// 非法输入必须走失败分支，而不是产出半截结果
    @Test("非法与空输入抛出 invalidJSON")
    func invalidInputThrows() {
        #expect(throws: JSONFormatterLogic.Failure.invalidJSON) {
            _ = try JSONFormatterLogic.prettyPrint("{", indent: 2)
        }
        #expect(throws: JSONFormatterLogic.Failure.invalidJSON) {
            _ = try JSONFormatterLogic.prettyPrint("", indent: 2)
        }
        #expect(throws: JSONFormatterLogic.Failure.invalidJSON) {
            _ = try JSONFormatterLogic.minify("{")
        }
        // 顶层裸片段默认不可解析，与视图原行为一致
        #expect(throws: JSONFormatterLogic.Failure.invalidJSON) {
            _ = try JSONFormatterLogic.minify("1")
        }
    }

    @Test("字节数按 1024 进位格式化")
    func byteSizeFormatting() {
        #expect(JSONFormatterLogic.byteSize("") == "0 B")
        #expect(JSONFormatterLogic.byteSize("abc") == "3 B")
        #expect(JSONFormatterLogic.byteSize(String(repeating: "a", count: 1023)) == "1023 B")
        #expect(JSONFormatterLogic.byteSize(String(repeating: "a", count: 1024)) == "1.0 KB")
    }
}

@MainActor
@Suite("JSON 格式化插件契约")
struct JSONFormatterPluginTests {

    @Test("元数据符合插件约定")
    func metadata() {
        #expect(JSONFormatterPlugin.id == "json-formatter")
        #expect(JSONFormatterPlugin.id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
        #expect(!JSONFormatterPlugin.name.isEmpty)
        #expect(!JSONFormatterPlugin.icon.isEmpty)
        #expect(!JSONFormatterPlugin.triggerWords.isEmpty)
    }

    @Test("命中触发词时返回唯一入口")
    func searchItemsReturnsSingleEntry() async {
        let plugin = JSONFormatterPlugin()
        let items = await plugin.searchItems(query: "json")
        #expect(items.count == 1)
        #expect(items.first?.pluginID == JSONFormatterPlugin.id)
    }

    @Test("未命中触发词时不返回结果")
    func searchItemsIgnoresUnrelatedQuery() async {
        let plugin = JSONFormatterPlugin()
        let items = await plugin.searchItems(query: "天气")
        #expect(items.isEmpty)
    }
}
