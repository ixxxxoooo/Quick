// Snippet.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 文本片段
struct Snippet: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var content: String
    var keyword: String?
    var category: String?
    var createdAt: Date
    var updatedAt: Date

    /// 预览文本（前 60 字符）
    var preview: String {
        let clean = content.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if clean.count <= 60 { return clean }
        return String(clean.prefix(60)) + "…"
    }

    init(title: String, content: String, keyword: String? = nil, category: String? = nil) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.keyword = keyword
        self.category = category
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
