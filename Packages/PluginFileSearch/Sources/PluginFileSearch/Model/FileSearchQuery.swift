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
}
