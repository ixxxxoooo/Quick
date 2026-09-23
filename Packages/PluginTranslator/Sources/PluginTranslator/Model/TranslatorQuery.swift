// TranslatorQuery.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 翻译插件的一次查询意图
public enum TranslatorIntent: Equatable, Sendable {
    /// 翻译一段文本
    case translate(String)
    /// 查一个词（词典）
    case dictionary(String)
}

/// 翻译插件的触发词解析
///
/// 纯逻辑：把「用户输入 → 要做什么」这一步单独拿出来，才能在测试里固定触发词的行为。
/// 触发词必须带尾随空格，否则分不出触发词和正文。
public enum TranslatorQuery {

    /// 翻译触发前缀
    public static let translatePrefixes = ["翻译 ", "tr ", "translate ", "fy "]

    /// 查词触发前缀
    public static let dictionaryPrefixes = ["词典 ", "dict ", "dictionary ", "查词 "]

    /// 解析输入意图
    ///
    /// - Parameter raw: 用户在搜索框里输入的原文
    /// - Returns: 解析出的意图；未命中前缀或正文为空时返回 nil
    public static func intent(in raw: String) -> TranslatorIntent? {
        let lower = raw.lowercased()
        if let prefix = translatePrefixes.first(where: { lower.hasPrefix($0) }) {
            let text = String(raw.dropFirst(prefix.count))
            return text.isEmpty ? nil : .translate(text)
        }
        if let prefix = dictionaryPrefixes.first(where: { lower.hasPrefix($0) }) {
            let text = String(raw.dropFirst(prefix.count))
            return text.isEmpty ? nil : .dictionary(text)
        }
        return nil
    }

    /// 兼容入口：只取待翻译文本
    ///
    /// - Parameter raw: 用户输入
    /// - Returns: 翻译意图里的正文；不是翻译意图时返回 nil
    public static func text(in raw: String) -> String? {
        if case .translate(let text) = intent(in: raw) { return text }
        return nil
    }
}
