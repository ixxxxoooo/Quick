// FileSearchQuery.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 文件搜索的触发词解析
///
/// 纯逻辑：把「用户输入 → 真正要搜的关键词」这一步单独拿出来，才能在不启动
/// Spotlight 的前提下固定触发词的行为（真正的查询由 FileSearchSession 交给
/// NSMetadataQuery）。
public enum FileSearchQuery {

    /// 触发前缀
    ///
    /// 必须带尾随空格。`f ` 排在 `file ` 前面不会互相抢：以 `file ` 开头的输入
    /// 第 2 个字符是 `i`，不满足 `f `（f 后面要是空格）。
    public static let prefixes = ["f ", "file ", "文件 "]

    /// 从用户输入里解析出搜索关键词
    ///
    /// - Parameter raw: 用户在搜索框里输入的原文
    /// - Returns: 去掉触发前缀后的关键词；未命中前缀或关键词为空时返回 nil
    public static func keyword(in raw: String) -> String? {
        guard let prefix = prefixes.first(where: { raw.lowercased().hasPrefix($0) }) else {
            return nil
        }
        let keyword = String(raw.dropFirst(prefix.count))
        return keyword.isEmpty ? nil : keyword
    }

    /// Spotlight 谓词的描述：格式串 + 参数
    ///
    /// 只描述「搜什么」，由会话交给 `NSPredicate`。抽成纯数据是为了让「搜索文件内容」
    /// 这个开关的效果能被断言 —— 真正跑查询需要 Spotlight 与整机索引，测试里不允许。
    struct Predicate: Equatable, Sendable {
        let format: String
        let arguments: [String]
    }

    /// 构造搜索谓词
    ///
    /// - Parameters:
    ///   - keyword: 关键词
    ///   - includeContents: 为 true 时连文件内的文本内容一起匹配（`kMDItemTextContent` 是 Spotlight 的内容索引）
    /// - Returns: 谓词描述
    static func predicate(for keyword: String, includeContents: Bool) -> Predicate {
        guard includeContents else {
            return Predicate(
                format: "kMDItemDisplayName CONTAINS[cd] %@",
                arguments: [keyword]
            )
        }
        return Predicate(
            format: "(kMDItemDisplayName CONTAINS[cd] %@) OR (kMDItemTextContent CONTAINS[cd] %@)",
            arguments: [keyword, keyword]
        )
    }
}
