// StringExtensions.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

public extension String {

    /// 模糊匹配：判断 self 是否包含 query 的所有字符（按顺序）
    /// - Parameter query: 搜索关键词
    /// - Returns: 是否匹配
    func fuzzyMatch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        var remaining = query.lowercased().makeIterator()
        guard var target = remaining.next() else { return true }
        for char in self.lowercased() {
            if char == target {
                guard let next = remaining.next() else { return true }
                target = next
            }
        }
        return false
    }

    /// 计算模糊匹配的相关度评分
    /// - Parameter query: 搜索关键词
    /// - Returns: 相关度（0.0 ~ 1.0，越高越相关）
    func fuzzyScore(_ query: String) -> Double {
        guard !query.isEmpty else { return 0 }
        let lower = self.lowercased()
        let queryLower = query.lowercased()

        // 完全匹配 → 最高分
        if lower == queryLower { return 1.0 }

        // 前缀匹配 → 高分
        if lower.hasPrefix(queryLower) { return 0.9 }

        // 包含匹配 → 中高分
        if lower.contains(queryLower) { return 0.7 }

        // 模糊匹配 → 中分
        if fuzzyMatch(query) { return 0.4 }

        return 0
    }
}
