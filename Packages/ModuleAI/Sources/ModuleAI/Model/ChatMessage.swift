// ChatMessage.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 对话消息
struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date

    enum Role: String, Sendable {
        case user
        case assistant
        case system
    }

    init(role: Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}
