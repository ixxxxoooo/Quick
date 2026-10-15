// AIChat.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 对话里的角色（system 提示词不进历史，每次请求时现拼）
public enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

/// 一条对话消息
public struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var role: ChatRole
    public var content: String
    public var createdAt: Date
    /// 生成这条回复的模型名（用户消息为 nil）
    public var model: String?
    /// 生成失败的原因；非 nil 时这条消息显示为错误，并提供重试
    public var failure: String?

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        createdAt: Date = Date(),
        model: String? = nil,
        failure: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.model = model
        self.failure = failure
    }
}

/// 一个对话会话
public struct ChatSession: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    /// 用户手动改过标题后不再被首条消息覆盖
    public var isTitleCustom: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    /// 这个会话上次用的模型；失效时回落到默认模型
    public var model: AIModelRef?
    public var messages: [ChatMessage]

    public static let untitled = "新对话"

    public init(
        id: UUID = UUID(),
        title: String = ChatSession.untitled,
        isTitleCustom: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        isPinned: Bool = false,
        model: AIModelRef? = nil,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.isTitleCustom = isTitleCustom
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isPinned = isPinned
        self.model = model
        self.messages = messages
    }

    public var isEmpty: Bool { messages.isEmpty }

    /// 由首条用户消息推出标题：取第一行非空文字，超长截断
    public static func derivedTitle(from text: String, limit: Int = 24) -> String {
        let firstLine =
            text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard !firstLine.isEmpty else { return untitled }
        guard firstLine.count > limit else { return firstLine }
        return String(firstLine.prefix(limit)) + "…"
    }

    /// 列表里第二行的预览：最后一条消息的首行
    public var preview: String {
        guard let last = messages.last(where: { $0.failure == nil }) else { return "" }
        return last.content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    /// 标题或任一条消息包含关键字（不区分大小写）
    public func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        if title.localizedCaseInsensitiveContains(needle) { return true }
        return messages.contains { $0.content.localizedCaseInsensitiveContains(needle) }
    }
}

/// 侧栏里的一个分组
public struct ChatSessionSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let sessions: [ChatSession]
}

/// 会话列表的组织规则：筛选、分组、容量、上下文裁剪
///
/// 全是纯函数：时钟与日历作为参数注入，测试不依赖当前时间。
public enum ChatSessions {

    /// 保留的会话上限；超出时淘汰最久没动过的未置顶会话
    public static let maxSessions = 200

    /// 一次请求最多带多少条历史消息
    public static let maxContextMessages = 40
    /// 历史消息总字数上限：长对话不能把请求撑到超出模型窗口
    public static let maxContextCharacters = 24_000

    /// 按「置顶 / 今天 / 昨天 / 过去 7 天 / 过去 30 天 / 更早」分组
    ///
    /// 组内按更新时间倒序；空组不出现。有搜索词时只保留命中的会话。
    public static func sections(
        _ sessions: [ChatSession],
        query: String = "",
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ChatSessionSection] {
        let visible = sessions.filter { $0.matches(query) }
            .sorted { $0.updatedAt > $1.updatedAt }

        let startOfToday = calendar.startOfDay(for: now)
        func daysAgo(_ session: ChatSession) -> Int {
            let day = calendar.startOfDay(for: session.updatedAt)
            return calendar.dateComponents([.day], from: day, to: startOfToday).day ?? 0
        }

        var buckets: [(id: String, title: String, sessions: [ChatSession])] = [
            ("pinned", "置顶", []), ("today", "今天", []), ("yesterday", "昨天", []),
            ("week", "过去 7 天", []), ("month", "过去 30 天", []), ("older", "更早", [])
        ]
        for session in visible {
            let index: Int
            if session.isPinned {
                index = 0
            } else {
                switch daysAgo(session) {
                case ...0: index = 1
                case 1: index = 2
                case 2...7: index = 3
                case 8...30: index = 4
                default: index = 5
                }
            }
            buckets[index].sessions.append(session)
        }
        return buckets.filter { !$0.sessions.isEmpty }
            .map { ChatSessionSection(id: $0.id, title: $0.title, sessions: $0.sessions) }
    }

    /// 恢复上次被中断的会话
    ///
    /// 生成途中退出应用，磁盘上会留着一条空内容、没有失败标记的助手消息；
    /// 原样加载会让它永远显示「正在思考…」。把它标成失败，用户能一键重试。
    public static func recoveringInterrupted(_ session: ChatSession) -> ChatSession {
        var result = session
        for index in result.messages.indices {
            let message = result.messages[index]
            if message.role == .assistant, message.content.isEmpty, message.failure == nil {
                result.messages[index].failure = "上次生成被中断"
            }
        }
        return result
    }

    /// 超出容量时应该淘汰的会话 id（最久没动过的未置顶会话）
    public static func evictions(_ sessions: [ChatSession], limit: Int = maxSessions) -> [UUID] {
        guard sessions.count > limit else { return [] }
        let removable = sessions.filter { !$0.isPinned }
            .sorted { $0.updatedAt < $1.updatedAt }
        return Array(removable.prefix(sessions.count - limit)).map(\.id)
    }

    /// 从历史里裁出本次请求要带的消息
    ///
    /// 从最新往回取，直到条数或字数用尽；失败的回复与空内容不带上（它们不是模型说的话）。
    /// 至少保留最后一条，哪怕它自己就超了字数。
    public static func contextMessages(
        _ messages: [ChatMessage],
        maxMessages: Int = maxContextMessages,
        maxCharacters: Int = maxContextCharacters
    ) -> [ChatMessage] {
        var picked: [ChatMessage] = []
        var characters = 0
        for message in messages.reversed() where message.failure == nil && !message.content.isEmpty {
            if picked.count >= maxMessages { break }
            if !picked.isEmpty, characters + message.content.count > maxCharacters { break }
            picked.append(message)
            characters += message.content.count
        }
        picked.reverse()
        // 请求必须以用户消息开头：Anthropic 不接受 assistant 开头，
        // 裁剪也可能恰好把用户消息切掉，只剩一条孤零零的回复
        while let first = picked.first, first.role != .user { picked.removeFirst() }

        // 失败的回复被跳过后，会出现连续两条同角色消息（用户连发了两次）；
        // 角色必须交替，所以把它们并成一条
        var merged: [ChatMessage] = []
        for message in picked {
            if var last = merged.last, last.role == message.role {
                last.content += "\n\n" + message.content
                merged[merged.count - 1] = last
            } else {
                merged.append(message)
            }
        }
        return merged
    }
}
