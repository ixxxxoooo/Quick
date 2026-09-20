// SQLFormatterPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing
@testable import PluginSQLFormatter

@Suite("SQL 格式化逻辑")
struct SQLFormatterLogicTests {

    @Test("关键字独占一行并统一大写")
    func formatUppercasesKeywords() {
        let result = SQLFormatterLogic.format("select a from t", indent: 2)
        #expect(result == "SELECT a\nFROM t")
    }

    /// 大小写混写也要归一，否则用户为了格式化得先把语句重打一遍
    @Test("大小写混写的关键字同样被识别")
    func formatIsCaseInsensitive() {
        let result = SQLFormatterLogic.format("Select id From users Where id = 1", indent: 2)
        #expect(result.contains("SELECT"))
        #expect(result.contains("FROM"))
        #expect(result.contains("WHERE"))
        #expect(!result.lowercased().contains("select id from"))
    }

    /// 缩进值是视图暴露的可调项，无论选 2 还是 4 都必须产出一致的分行结果
    @Test("缩进参数不影响分行结果")
    func indentDoesNotChangeLineBreaks() {
        let two = SQLFormatterLogic.format("select a from t", indent: 2)
        let four = SQLFormatterLogic.format("select a from t", indent: 4)
        #expect(two == four)
        #expect(two.components(separatedBy: "\n").count == 2)
    }

    @Test("格式化清掉多余空行")
    func formatDropsBlankLines() {
        let result = SQLFormatterLogic.format("select a\n\n\nfrom t", indent: 2)
        #expect(!result.contains("\n\n"))
        #expect(result.components(separatedBy: "\n").allSatisfy { !$0.isEmpty })
    }

    @Test("压缩把折行归一成单个空格")
    func minifyCollapsesWhitespace() {
        let result = SQLFormatterLogic.minify("SELECT\n  a\nFROM   t")
        #expect(result == "SELECT a FROM t")
    }

    @Test("语句条数按分号统计并忽略空段")
    func countsStatements() {
        #expect(SQLFormatterLogic.statementCount(in: "") == 0)
        #expect(SQLFormatterLogic.statementCount(in: "select 1") == 1)
        #expect(SQLFormatterLogic.statementCount(in: "select 1; select 2;") == 2)
        #expect(SQLFormatterLogic.statementCount(in: "select 1;\n\n;") == 1)
    }

    @Test("字节数按 1024 进位格式化")
    func byteSizeFormatting() {
        #expect(SQLFormatterLogic.byteSize("abc") == "3 B")
        #expect(SQLFormatterLogic.byteSize(String(repeating: "a", count: 1024)) == "1.0 KB")
    }
}

@MainActor
@Suite("SQL 格式化插件契约")
struct SQLFormatterPluginTests {

    @Test("元数据符合插件约定")
    func metadata() {
        #expect(SQLFormatterPlugin.id == "sql-formatter")
        #expect(SQLFormatterPlugin.id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
        #expect(!SQLFormatterPlugin.name.isEmpty)
        #expect(!SQLFormatterPlugin.icon.isEmpty)
        #expect(!SQLFormatterPlugin.triggerWords.isEmpty)
    }

    @Test("命中触发词时返回唯一入口")
    func searchItemsReturnsSingleEntry() async {
        let plugin = SQLFormatterPlugin()
        let items = await plugin.searchItems(query: "sql")
        #expect(items.count == 1)
        #expect(items.first?.pluginID == SQLFormatterPlugin.id)
    }

    @Test("未命中触发词时不返回结果")
    func searchItemsIgnoresUnrelatedQuery() async {
        let plugin = SQLFormatterPlugin()
        let items = await plugin.searchItems(query: "天气")
        #expect(items.isEmpty)
    }
}
