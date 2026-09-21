// PasteContentDetector.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 粘贴内容类型检测器
///
/// 在主搜索框中粘贴文本时，自动识别内容类型并跳转到对应插件。
/// 检测逻辑是纯函数，不依赖插件实例，方便测试。
public enum PasteContentDetector {

    /// 检测到的内容类型
    public enum ContentKind: Sendable, Equatable {
        /// JSON 文本 → 跳转 JSON 格式化
        case json
        /// SQL 语句 → 跳转 SQL 格式化
        case sql
        /// 无法识别或普通文本
        case unknown
    }

    /// 判断一段文本是否为粘贴操作（而非逐字输入）
    ///
    /// 逐字输入每次 onChange 只增加 1~2 个字符，粘贴则一次性灌入大量文本。
    /// 阈值取 10 个字符：短于此长度的 JSON/SQL 不太有格式化需求。
    public static let pasteThreshold = 10

    /// 检测文本的内容类型
    ///
    /// - Parameter text: 待检测的文本
    /// - Returns: 识别到的内容类型
    public static func detect(_ text: String) -> ContentKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= pasteThreshold else { return .unknown }

        if looksLikeJSON(trimmed) { return .json }
        if looksLikeSQL(trimmed) { return .sql }
        return .unknown
    }

    /// JSON 检测：以 { 或 [ 开头，并能被 JSONSerialization 解析
    private static func looksLikeJSON(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[" else { return false }
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// SQL 检测：以常见 SQL 关键字开头
    ///
    /// 不做完整语法解析 —— 只需要覆盖「开发者粘贴一段 SQL 到搜索框」这个场景。
    /// 误判代价很低（用户按返回即可回到搜索），漏判代价也低（手动切到 SQL 插件）。
    private static func looksLikeSQL(_ text: String) -> Bool {
        let upper = text.uppercased()
        let sqlKeywords = [
            "SELECT ", "INSERT ", "UPDATE ", "DELETE ", "CREATE ", "ALTER ",
            "DROP ", "WITH ", "EXPLAIN ", "MERGE ", "REPLACE ",
            "SELECT\n", "INSERT\n", "UPDATE\n", "DELETE\n", "CREATE\n",
            "ALTER\n", "DROP\n", "WITH\n"
        ]
        return sqlKeywords.contains { upper.hasPrefix($0) }
    }
}
