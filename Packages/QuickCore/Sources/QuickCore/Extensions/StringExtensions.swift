// StringExtensions.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

public extension String {

    /// 匹配形态：折叠过的原文 + 拼音转写
    var matchText: MatchText { MatchText(self) }

    /// 模糊匹配：判断 self 是否能对应到 query
    ///
    /// 空查询按「匹配」处理 —— 调用方用空查询表示「没有筛选条件」。
    ///
    /// - Parameter query: 搜索关键词
    /// - Returns: 是否匹配
    func fuzzyMatch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return fuzzyScore(query) > 0
    }

    /// 模糊匹配的相关度评分（0.0 ~ 1.0，越高越靠前）
    ///
    /// 每次调用都会重新折叠候选、重新取拼音。候选多的时候（应用索引）别用它 ——
    /// 用 `MatchQuery` + `MatchText` 把两边各预处理一遍，别在循环里重复折叠。
    ///
    /// - Parameter query: 搜索关键词
    /// - Returns: 相关度（0 表示不匹配）
    func fuzzyScore(_ query: String) -> Double {
        MatchQuery(query).score(matchText)
    }
}
