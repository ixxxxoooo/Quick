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

// MARK: - 节点文本

@Suite("JSON 节点文本")
struct JSONNodeTextTests {

    /// 复制出去的必须是**合法 JSON**：键与字符串值里的引号、反斜杠、控制字符都要转义，
    /// 否则用户粘到编辑器里就是一段语法错误的文本。
    @Test("紧凑文本转义引号、反斜杠与控制字符")
    func compactTextEscapes() {
        let node = JSONNode.object([
            JSONNode.Pair(key: "quote\"key", value: .string("line1\nline2\\end\ttab")),
            JSONNode.Pair(key: "control", value: .string("\u{01}"))
        ])

        let text = node.compactText()
        #expect(text.contains(#""quote\"key""#))
        #expect(text.contains(#"\n"#))
        #expect(text.contains(#"\\end"#))
        #expect(text.contains(#"\t"#))
        #expect(text.contains(#"\u0001"#))
        // 转义之后仍要能被解析回来
        #expect((try? JSONFormatterLogic.parseTree(text)) != nil)
    }

    /// 整数值不能输出成 `1.0` —— 用户拿它当 ID 用时会被下游当成浮点
    @Test("整数按整数输出，小数保持原样")
    func numberTextKeepsIntegersIntegral() {
        #expect(JSONNode.numberText(1) == "1")
        #expect(JSONNode.numberText(-42) == "-42")
        #expect(JSONNode.numberText(1.5) == "1.5")
        // 超出 Int64 精确范围的值不能再当成整数取整
        #expect(JSONNode.numberText(1e20) != "100000000000000000000")
    }

    /// 路径是折叠状态的键，同一种结构必须每次得到同一个路径 —— 否则折叠会错位
    @Test("同名键与嵌套数组的路径互不冲突")
    func rowPathsAreDistinct() throws {
        let root = try JSONFormatterLogic.parseTree(#"{"a":[{"a":1}],"b":[{"a":2}]}"#)
        let rows = JSONTreeLayout.rows(
            root: root, collapsed: JSONTreeLayout.defaultCollapsed(root), query: "1")

        let ids = rows.map(\.id)
        #expect(Set(ids).count == ids.count, "路径必须唯一，重复会让 ForEach 进入未定义行为")
        #expect(ids.contains { $0.contains("[\"a\"]") })
        #expect(ids.contains { $0.contains("[0]") })
    }

    @Test("搜索只命中叶子，不因容器子节点命中而重复标记")
    func searchMarksOnlyMatchingLeaves() throws {
        let root = try JSONFormatterLogic.parseTree(#"{"outer":{"inner":"findme"}}"#)
        let rows = JSONTreeLayout.rows(
            root: root, collapsed: JSONTreeLayout.defaultCollapsed(root), query: "findme")

        let matched = rows.filter(\.matchesQuery)
        #expect(matched.count == 1, "只有叶子自身命中，容器不该被一起标记")
        #expect(matched.first?.key == "inner")
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

    /// 入口由静态命令承载，不再由搜索现算 —— 原来这条测试问的是 `searchItems` 的返回，
    /// 那个遗留 API 已删除（见 docs/refactor-plan.md Phase 0）。
    @Test("格式化与压缩各有一条命令，且功能命令带插件前缀")
    func commandsCoverBothDirections() {
        let commands = JSONFormatterPlugin.commands
        let ids = commands.map(\.id)

        #expect(ids.contains("json-formatter.format"))
        #expect(ids.contains("json-formatter.minify"))
        let functionIDs = commands.filter { !$0.id.hasPrefix("plugin.open.") }.map(\.id)
        #expect(functionIDs.allSatisfy { $0.hasPrefix("json-formatter.") })
        #expect(commands.allSatisfy { $0.pluginID == JSONFormatterPlugin.id })
    }

    @Test("插件不参与按查询现算")
    func doesNotTakePartInDynamicSearch() async {
        let plugin = JSONFormatterPlugin()

        #expect(!plugin.accepts(query: "json"))
        #expect(await plugin.dynamicSearch(query: "天气").isEmpty)
    }
}
