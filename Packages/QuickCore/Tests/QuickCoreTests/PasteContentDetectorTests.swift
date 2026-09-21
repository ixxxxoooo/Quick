// PasteContentDetectorTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import QuickCore

@Suite("PasteContentDetector")
struct PasteContentDetectorTests {

    // MARK: - JSON 检测

    @Test("有效 JSON 对象被识别")
    func detectsJSONObject() {
        let json = """
            {"name": "Quick", "version": "1.0", "plugins": ["clipboard", "calculator"]}
            """
        #expect(PasteContentDetector.detect(json) == .json)
    }

    @Test("有效 JSON 数组被识别")
    func detectsJSONArray() {
        let json = """
            [{"id": 1, "name": "test"}, {"id": 2, "name": "demo"}]
            """
        #expect(PasteContentDetector.detect(json) == .json)
    }

    @Test("格式化的多行 JSON 被识别")
    func detectsMultilineJSON() {
        let json = """
            {
                "key": "value",
                "number": 42,
                "nested": {
                    "array": [1, 2, 3]
                }
            }
            """
        #expect(PasteContentDetector.detect(json) == .json)
    }

    @Test("无效 JSON 不被误判")
    func rejectsInvalidJSON() {
        let notJSON = "{this is not valid json at all}"
        #expect(PasteContentDetector.detect(notJSON) == .unknown)
    }

    // MARK: - SQL 检测

    @Test("SELECT 语句被识别")
    func detectsSelect() {
        let sql = "SELECT id, name FROM users WHERE active = 1 ORDER BY created_at DESC"
        #expect(PasteContentDetector.detect(sql) == .sql)
    }

    @Test("INSERT 语句被识别")
    func detectsInsert() {
        let sql = "INSERT INTO users (name, email) VALUES ('test', 'test@example.com')"
        #expect(PasteContentDetector.detect(sql) == .sql)
    }

    @Test("多行 SQL 被识别")
    func detectsMultilineSQL() {
        let sql = """
            SELECT
                u.id,
                u.name,
                o.total
            FROM users u
            JOIN orders o ON u.id = o.user_id
            WHERE o.created_at > '2024-01-01'
            """
        #expect(PasteContentDetector.detect(sql) == .sql)
    }

    @Test("CREATE TABLE 被识别")
    func detectsCreateTable() {
        let sql = "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)"
        #expect(PasteContentDetector.detect(sql) == .sql)
    }

    @Test("小写 SQL 也被识别")
    func detectsLowercaseSQL() {
        let sql = "select * from users where id = 1"
        #expect(PasteContentDetector.detect(sql) == .sql)
    }

    // MARK: - 普通文本

    @Test("普通文本不被识别")
    func rejectsPlainText() {
        let text = "这是一段普通的中文文本，不是 JSON 也不是 SQL"
        #expect(PasteContentDetector.detect(text) == .unknown)
    }

    @Test("短文本不触发检测")
    func rejectsShortText() {
        #expect(PasteContentDetector.detect("{\"a\":1}") == .unknown)
        #expect(PasteContentDetector.detect("SELECT 1") == .unknown)
    }

    @Test("空文本不触发检测")
    func rejectsEmpty() {
        #expect(PasteContentDetector.detect("") == .unknown)
        #expect(PasteContentDetector.detect("   ") == .unknown)
    }
}
