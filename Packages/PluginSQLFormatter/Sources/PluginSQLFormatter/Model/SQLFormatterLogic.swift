// SQLFormatterLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// SQL 格式化的纯逻辑
///
/// 从视图里抽出来是为了能脱离 SwiftUI 单独测试 —— `Model/` 不允许 import
/// SwiftUI/AppKit（仓库红线，靠 grep 保证），视图只负责把结果写进 @State。
enum SQLFormatterLogic {

    /// 需要独占一行的关键字
    ///
    /// 顺序有意义：`JOIN` 排在 `LEFT JOIN` 前面，先被替换成带换行的形式之后，
    /// 多词关键字就再也匹配不上了。想改顺序先想清楚这一点。
    private static let keywords = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "JOIN", "LEFT JOIN",
        "RIGHT JOIN", "INNER JOIN", "OUTER JOIN", "CROSS JOIN", "ON",
        "GROUP BY", "ORDER BY", "HAVING", "INSERT INTO", "VALUES",
        "UPDATE", "SET", "DELETE FROM", "CREATE TABLE", "ALTER TABLE",
        "DROP TABLE", "LIMIT", "OFFSET", "UNION", "UNION ALL",
        "CASE", "WHEN", "THEN", "ELSE", "END", "AS"
    ]

    /// 格式化：关键字独占一行并统一大写
    ///
    /// 顺带把每行前导空格清掉，否则双击格式化的结果会一层层往外漂。
    static func format(_ input: String, indent: Int) -> String {
        let indentStr = String(repeating: " ", count: indent)
        var result = input
        // 在关键词前加换行和缩进
        for keyword in keywords {
            result = result.replacingOccurrences(
                of: "\\b\(keyword)\\b",
                with: "\n\(indentStr)\(keyword)",
                options: [.caseInsensitive, .regularExpression]
            )
        }

        // 清理多余空行和前导空格
        return result.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .init(charactersIn: " ")) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// 压缩：折行与连续空白归一成单个空格
    static func minify(_ input: String) -> String {
        input.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// 语句条数（按分号切分，忽略空段）
    static func statementCount(in input: String) -> Int {
        input.components(separatedBy: ";").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    /// 人类可读的字节数
    static func byteSize(_ text: String) -> String {
        let bytes = text.utf8.count
        if bytes < 1024 { return "\(bytes) B" }
        return String(format: "%.1f KB", Double(bytes) / 1024)
    }
}
