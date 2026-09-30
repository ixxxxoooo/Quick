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

    @Test("关键字小写模式统一输出小写关键字并保留标识符大小写")
    func formatLowercasesKeywordsWhenRequested() {
        let result = SQLFormatterLogic.format(
            "SELECT userId AS uid FROM UserTable WHERE userId IN (1, 2) ORDER BY uid DESC",
            indent: 2,
            keywordCase: .lowercase
        )
        #expect(result == "select userId as uid\nfrom UserTable\nwhere userId in (1, 2)\norder by uid desc")
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

    @Test("缩进参数控制从属子句与子查询的缩进宽度且重复格式化幂等")
    func indentControlsSubclauseAndIsIdempotent() {
        let sql = "select * from users u left join orders o on u.id = o.user_id where u.status = 1 and o.amount > 10"
        let two = SQLFormatterLogic.format(sql, indent: 2)
        let four = SQLFormatterLogic.format(sql, indent: 4)

        #expect(two.contains("\n  ON u.id = o.user_id"))
        #expect(two.contains("\n  AND o.amount > 10"))
        #expect(four.contains("\n    ON u.id = o.user_id"))
        #expect(four.contains("\n    AND o.amount > 10"))

        // 重复格式化不会继续累加缩进
        let formattedTwice = SQLFormatterLogic.format(two, indent: 2)
        #expect(formattedTwice == two)
    }

    @Test("子查询括号自动换行缩进，普通括号与函数调用保持行内")
    func subqueryIndentationAndInlineParens() {
        let sql = "select count(*), id from users where id in (select user_id from orders where total > 100) and status in (1, 2)"
        let result = SQLFormatterLogic.format(sql, indent: 2)
        let expected = """
            SELECT COUNT(*), id
            FROM users
            WHERE id IN (
              SELECT user_id
              FROM orders
              WHERE total > 100
            )
              AND status IN (1, 2)
            """
        #expect(result == expected)
    }

    @Test("BETWEEN 表达式内的 AND 保持在同一行，不误拆为 WHERE 条件行")
    func betweenAndStaysInline() {
        let sql = "select * from logs where created_at between '2026-01-01' and '2026-12-31' and level = 'error'"
        let result = SQLFormatterLogic.format(sql, indent: 2)
        let expected = """
            SELECT *
            FROM logs
            WHERE created_at BETWEEN '2026-01-01' AND '2026-12-31'
              AND level = 'error'
            """
        #expect(result == expected)
    }

    @Test("CASE WHEN THEN ELSE END 结构化缩进")
    func caseWhenIndentation() {
        let sql = "select id, case when score >= 90 then 'A' else 'B' end as grade from exams"
        let result = SQLFormatterLogic.format(sql, indent: 2)
        let expected = """
            SELECT id, CASE
              WHEN score >= 90 THEN 'A'
              ELSE 'B'
            END AS grade
            FROM exams
            """
        #expect(result == expected)
    }

    @Test("格式化清掉多余空行")
    func formatDropsBlankLines() {
        let result = SQLFormatterLogic.format("select a\n\n\nfrom t", indent: 2)
        #expect(!result.contains("\n\n"))
        #expect(result.components(separatedBy: "\n").allSatisfy { !$0.isEmpty })
    }

    /// 字符串字面量整体透传，关键字形态的内容不能被插入换行
    @Test("格式化不改写字符串字面量内部的关键字与转义引号")
    func formatPreservesStringLiterals() {
        let result = SQLFormatterLogic.format(
            #"select * from t where name = 'FROM' or note = 'it\'s SELECT x' or tag = 'a''b'"#,
            indent: 2
        )
        #expect(result.contains("'FROM'"))
        #expect(result.contains(#"'it\'s SELECT x'"#))
        #expect(result.contains("'a''b'"))
        #expect(!result.contains("\nFROM'"))
        #expect(!result.contains("\nSELECT x'"))
    }

    /// 多词子句作为整体换行，`LEFT JOIN` / `LEFT OUTER JOIN` 不能被拆开；限定名与类型转换紧贴
    @Test("多词关键字与限定名的间距保持正确")
    func formatKeepsMultiWordClausesTogether() {
        let result = SQLFormatterLogic.format(
            "select a.id::text from a left join b on a.id = b.id left outer join c on b.id = c.id",
            indent: 2
        )
        #expect(result.contains("LEFT JOIN b"))
        #expect(result.contains("LEFT OUTER JOIN c"))
        #expect(!result.contains("\nJOIN b"))
        #expect(result.contains("a.id = b.id"))
        #expect(result.contains("a.id::text"))
        #expect(!result.contains("a. id"))
    }

    @Test("命名参数、变量、MyBatis 占位符与方括号标识符不被拆碎")
    func formatPreservesPlaceholdersAndBracketIdentifiers() {
        let sql = "select [user_id] from ${table_name} where id = :user_id and dept = #{deptId} and org = $1 and tz = @@time_zone"
        let result = SQLFormatterLogic.format(sql, indent: 2)
        #expect(result.contains("[user_id]"))
        #expect(result.contains("${table_name}"))
        #expect(result.contains(":user_id"))
        #expect(result.contains("#{deptId}"))
        #expect(result.contains("$1"))
        #expect(result.contains("@@time_zone"))
    }

    /// 裸 UNION 与 UNION ALL 是两个词法形态：前者单词、后者双词，都必须独占一行
    @Test("UNION 与 UNION ALL 都独占一行")
    func formatHandlesUnionVariants() {
        let result = SQLFormatterLogic.format("select 1 union select 2 union all select 3", indent: 2)
        #expect(result == "SELECT 1\nUNION\nSELECT 2\nUNION ALL\nSELECT 3")
    }

    @Test("CRLF 行尾的单行注释不会吞噬后续 SQL 语句")
    func formatHandlesLineCommentsWithCRLF() {
        let sql = "select a -- comment line\r\nfrom users where id = 1"
        let result = SQLFormatterLogic.format(sql, indent: 2)
        let expected = """
            SELECT a -- comment line
            FROM users
            WHERE id = 1
            """
        #expect(result == expected)
    }

    @Test("SELECT 投影字段较多时自动每行一个字段并缩进")
    func formatBreaksMultiItemSelectList() {
        let sql = "select id, user_name, email, status, created_at from users where status = 1"
        let result = SQLFormatterLogic.format(sql, indent: 2)
        let expected = """
            SELECT
              id,
              user_name,
              email,
              status,
              created_at
            FROM users
            WHERE status = 1
            """
        #expect(result == expected)
    }

    @Test("压缩保留字符串字面量内部的空白")
    func minifyPreservesLiteralWhitespace() {
        let result = SQLFormatterLogic.minify("SELECT 'x  y'\nFROM t")
        #expect(result == "SELECT 'x  y' FROM t")
    }

    @Test("压缩把折行归一成单个空格并支持关键字大小写转换")
    func minifyCollapsesWhitespace() {
        let result = SQLFormatterLogic.minify("SELECT\n  a\nFROM   t")
        #expect(result == "SELECT a FROM t")

        let lower = SQLFormatterLogic.minify("SELECT\n  a\nFROM   t", keywordCase: .lowercase)
        #expect(lower == "select a from t")
    }

    @Test("语句条数与行数统计")
    func countsStatementsAndLines() {
        #expect(SQLFormatterLogic.statementCount(in: "") == 0)
        #expect(SQLFormatterLogic.statementCount(in: "select 1") == 1)
        #expect(SQLFormatterLogic.statementCount(in: "select 1; select 2;") == 2)
        #expect(SQLFormatterLogic.statementCount(in: "select 1;\n\n;") == 1)

        #expect(SQLFormatterLogic.lineCount(in: "") == 0)
        #expect(SQLFormatterLogic.lineCount(in: "SELECT 1\nFROM t") == 2)
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

    /// 单面板插件只暴露唯一入口命令，触发词收敛到 `triggerWords`。
    @Test("单面板插件只暴露打开插件入口命令")
    func commandsCoverBothDirections() {
        let commands = SQLFormatterPlugin.commands
        #expect(commands.map(\.id) == ["plugin.open.sql-formatter"])
        #expect(commands.allSatisfy { $0.pluginID == SQLFormatterPlugin.id })
    }

    @Test("插件不参与按查询现算")
    func doesNotTakePartInDynamicSearch() async {
        let plugin = SQLFormatterPlugin()

        #expect(!plugin.accepts(query: "sql"))
        #expect(await plugin.dynamicSearch(query: "天气").isEmpty)
    }
}
