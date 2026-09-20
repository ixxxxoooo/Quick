// TranslatorQuery.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 翻译插件的触发词解析
///
/// 纯逻辑：把「用户输入 → 真正要翻译的文本」这一步单独拿出来，
/// 才能在测试里固定触发词的行为（真正的翻译由 TranslationService 负责）。
public enum TranslatorQuery {

    /// 触发前缀
    ///
    /// 必须带尾随空格：没有空格就分不出触发词和正文（`tr` 与 `translate` 也因此
    /// 互不干扰 —— 先命中 `tr ` 的查询不可能同时以 `translate ` 开头）。
    public static let prefixes = ["翻译 ", "tr ", "translate ", "fy "]

    /// 从用户输入里解析出待翻译文本
    ///
    /// - Parameter raw: 用户在搜索框里输入的原文
    /// - Returns: 去掉触发前缀后的文本；未命中前缀或正文为空时返回 nil
    public static func text(in raw: String) -> String? {
        guard let prefix = prefixes.first(where: { raw.lowercased().hasPrefix($0) }) else {
            return nil
        }
        let text = String(raw.dropFirst(prefix.count))
        return text.isEmpty ? nil : text
    }
}
