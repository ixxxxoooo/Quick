// NoteModel.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 笔记条目
struct NoteItem: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var content: String
    var category: NoteCategory
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date

    var preview: String {
        let clean = content.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return clean.count <= 60 ? clean : String(clean.prefix(60)) + "…"
    }

    init(title: String, content: String = "", category: NoteCategory = .note) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.category = category
        self.isPinned = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// 从数据库的一行还原
    ///
    /// 与上面的初始化器不同，这个不生成新 id、不覆盖时间戳 —— 还原的是已经存在过的
    /// 笔记，任何「当作新笔记」的默认值都会让身份与时间在每次读取时漂移。
    init(
        id: UUID,
        title: String,
        content: String,
        category: NoteCategory,
        isPinned: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 笔记类别
enum NoteCategory: String, Codable, CaseIterable, Sendable {
    case note = "笔记"
    case todo = "待办"
    case sticky = "便签"

    var icon: String {
        switch self {
        case .note: "note.text"
        case .todo: "checklist"
        case .sticky: "note"
        }
    }
}

/// 待办项
struct TodoItem: Identifiable, Codable, Sendable {
    let id: UUID
    var text: String
    var isCompleted: Bool
    var createdAt: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.isCompleted = false
        self.createdAt = Date()
    }

    /// 从数据库的一行还原（不生成新 id、不覆盖时间戳，理由同 `NoteItem`）
    init(id: UUID, text: String, isCompleted: Bool, createdAt: Date) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}
