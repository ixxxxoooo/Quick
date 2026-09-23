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

    /// 4 空格缩进只能改行首，字符串值内部的空格必须原样保留
    @Test("4 空格缩进不改动字符串值内部的空格")
    func fourSpaceIndentKeepsStringInnerSpaces() throws {
        let result = try JSONFormatterLogic.prettyPrint(#"{"a":"x  y"}"#, indent: 4)
        #expect(result.text.contains("\"x  y\""))
        #expect(!result.text.contains("\"x    y\""))
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

    // MARK: - 反转义

    @Test("带引号的转义 JSON 字符串被还原")
    func unescapesQuotedString() throws {
        let decoded = try JSONFormatterLogic.unescape(#""{\"a\":1,\n\"b\":\"x\"}""#)
        #expect(decoded == "{\"a\":1,\n\"b\":\"x\"}")
        // 还原后应该是合法 JSON
        #expect((try? JSONFormatterLogic.parseTree(decoded)) != nil)
    }

    @Test("裸的转义正文也能还原")
    func unescapesBareEscapedBody() throws {
        let decoded = try JSONFormatterLogic.unescape(#"{\"a\":1,\"b\":2}"#)
        #expect(decoded == #"{"a":1,"b":2}"#)
    }

    @Test("自动反转义只在不影响正常 JSON 时生效")
    func autoUnescapeIsConservative() {
        // 正常 JSON 原样返回
        #expect(JSONFormatterLogic.autoUnescape(#"{"a":1}"#) == #"{"a":1}"#)
        // 普通文本不动
        #expect(JSONFormatterLogic.autoUnescape("hello") == "hello")
        // 被转义的 JSON 会被还原
        #expect(JSONFormatterLogic.autoUnescape(#"{\"a\":1}"#) == #"{"a":1}"#)
    }

    // MARK: - 树

    @Test("解析出带排序键的节点树并统计节点数")
    func parsesTree() throws {
        let root = try JSONFormatterLogic.parseTree(#"{"b":1,"a":[true,null]}"#)
        #expect(root.nodeCount == 5)
        guard case .object(let pairs) = root else {
            Issue.record("根应为对象")
            return
        }
        #expect(pairs.map(\.key) == ["a", "b"])
    }

    @Test("默认只展开根，其余容器折叠成计数")
    func defaultCollapsedShowsTopLevel() throws {
        let root = try JSONFormatterLogic.parseTree(#"{"a":{"b":{"c":1}},"d":2}"#)
        let rows = JSONTreeLayout.rows(
            root: root, collapsed: JSONTreeLayout.defaultCollapsed(root), query: "")
        // 根 + a + d；a 折叠后不再往下
        #expect(rows.map(\.depth) == [0, 1, 1])
        #expect(rows[1].value == "{1}")
        #expect(rows[1].isCollapsed)
    }

    @Test("搜索命中时自动展开命中路径")
    func searchExpandsMatches() throws {
        let root = try JSONFormatterLogic.parseTree(#"{"a":{"needle":1},"b":2}"#)
        let rows = JSONTreeLayout.rows(
            root: root, collapsed: JSONTreeLayout.defaultCollapsed(root), query: "needle")
        // 命中路径被展开：根 → a → needle
        #expect(rows.contains { $0.key == "needle" && $0.matchesQuery })
        #expect(!rows.contains { $0.isCollapsed && $0.key == "a" })
    }

    @Test("折叠全部后只剩根一行")
    func collapseAllLeavesRoot() throws {
        let root = try JSONFormatterLogic.parseTree(#"{"a":{"b":1}}"#)
        let rows = JSONTreeLayout.rows(root: root, collapsed: JSONTreeLayout.allCollapsed(root), query: "")
        #expect(rows.count == 1)
        #expect(rows[0].isCollapsed)
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
