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
}
