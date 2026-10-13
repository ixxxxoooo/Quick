// ChatSessionTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickCore

/// 固定在上海时区、2026-10-14 15:00，保证「今天 / 昨天」的判定不随运行时间变化
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}()

private let now: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 10
    components.day = 14
    components.hour = 15
    return calendar.date(from: components)!
}()

private func session(
    _ title: String, daysAgo: Int, pinned: Bool = false, messages: [ChatMessage] = []
) -> ChatSession {
    let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
    return ChatSession(
        title: title, createdAt: date, updatedAt: date, isPinned: pinned, messages: messages)
}

private func message(_ role: ChatRole, _ text: String, failure: String? = nil) -> ChatMessage {
    ChatMessage(role: role, content: text, failure: failure)
}

@Suite("会话标题与预览")
struct ChatSessionTitleTests {

    @Test("标题取首行非空文字")
    func firstLine() {
        #expect(ChatSession.derivedTitle(from: "\n\n  你好  \n第二行") == "你好")
    }

    @Test("超长标题截断并加省略号")
    func truncates() {
        let title = ChatSession.derivedTitle(from: String(repeating: "字", count: 40), limit: 10)
        #expect(title == String(repeating: "字", count: 10) + "…")
    }

    @Test("空文本回落到占位标题")
    func emptyFallsBack() {
        #expect(ChatSession.derivedTitle(from: "  \n ") == ChatSession.untitled)
    }

    @Test("预览取最后一条非失败消息的首行")
    func previewSkipsFailures() {
        let chat = ChatSession(messages: [
            message(.user, "问题"),
            message(.assistant, "回答第一行\n第二行"),
            message(.assistant, "", failure: "超时")
        ])
        #expect(chat.preview == "回答第一行")
        #expect(ChatSession().preview == "")
    }

    @Test("搜索同时匹配标题与正文，不区分大小写，空词全部命中")
    func matching() {
        let chat = ChatSession(title: "Swift 并发", messages: [message(.user, "什么是 Actor")])
        #expect(chat.matches("swift"))
        #expect(chat.matches("actor"))
        #expect(!chat.matches("rust"))
        #expect(chat.matches("   "))
    }
}

@Suite("会话分组")
struct ChatSessionGroupingTests {

    @Test("按时间分组，空组不出现，组内按更新时间倒序")
    func groups() {
        let sessions = [
            session("更早", daysAgo: 90),
            session("今天旧", daysAgo: 0),
            session("昨天", daysAgo: 1),
            session("三天前", daysAgo: 3),
            session("二十天前", daysAgo: 20),
            session("置顶的", daysAgo: 50, pinned: true)
        ]
        let sections = ChatSessions.sections(sessions, now: now, calendar: calendar)
        #expect(sections.map(\.title) == ["置顶", "今天", "昨天", "过去 7 天", "过去 30 天", "更早"])
        #expect(sections.first?.sessions.map(\.title) == ["置顶的"])
    }

    @Test("边界：7 天算「过去 7 天」，8 天算「过去 30 天」")
    func boundaries() {
        let sections = ChatSessions.sections(
            [session("七天", daysAgo: 7), session("八天", daysAgo: 8)], now: now, calendar: calendar)
        #expect(sections.map(\.title) == ["过去 7 天", "过去 30 天"])
    }

    @Test("今天里的会话按最近更新排在前面")
    func sortedWithinGroup() {
        let early = session("早", daysAgo: 0)
        var late = session("晚", daysAgo: 0)
        late.updatedAt = early.updatedAt.addingTimeInterval(60)
        let sections = ChatSessions.sections([early, late], now: now, calendar: calendar)
        #expect(sections.first?.sessions.map(\.title) == ["晚", "早"])
    }

    @Test("搜索只保留命中的会话，没命中时没有分组")
    func filtering() {
        let sessions = [session("Swift", daysAgo: 0), session("菜谱", daysAgo: 0)]
        let hit = ChatSessions.sections(sessions, query: "swift", now: now, calendar: calendar)
        #expect(hit.flatMap(\.sessions).map(\.title) == ["Swift"])
        #expect(ChatSessions.sections(sessions, query: "zzz", now: now, calendar: calendar).isEmpty)
    }
}

@Suite("会话容量")
struct ChatSessionEvictionTests {

    @Test("没超上限不淘汰")
    func underLimit() {
        let sessions = (0..<3).map { session("s\($0)", daysAgo: $0) }
        #expect(ChatSessions.evictions(sessions, limit: 3).isEmpty)
    }

    @Test("超出时淘汰最久没动过的，置顶的不动")
    func evictsOldestUnpinned() {
        let oldPinned = session("置顶旧", daysAgo: 100, pinned: true)
        let oldest = session("最旧", daysAgo: 50)
        let older = session("较旧", daysAgo: 10)
        let fresh = session("新", daysAgo: 0)
        let evicted = ChatSessions.evictions([oldPinned, oldest, older, fresh], limit: 2)
        #expect(Set(evicted) == [oldest.id, older.id])
    }

    @Test("全是置顶时宁可超限也不删")
    func allPinned() {
        let sessions = (0..<4).map { session("p\($0)", daysAgo: $0, pinned: true) }
        #expect(ChatSessions.evictions(sessions, limit: 2).isEmpty)
    }
}

@Suite("上下文裁剪")
struct ChatContextTests {

    @Test("跳过失败的回复，并把由此产生的连续用户消息合并")
    func skipsFailuresAndMerges() {
        let messages = [
            message(.user, "第一问"),
            message(.assistant, "", failure: "超时"),
            message(.user, "再问一次"),
            message(.assistant, "回答")
        ]
        let context = ChatSessions.contextMessages(messages)
        #expect(context.map(\.role) == [.user, .assistant])
        #expect(context.first?.content == "第一问\n\n再问一次")
    }

    @Test("条数超限时保留最新的")
    func messageLimit() {
        let messages = (0..<10).map { message($0 % 2 == 0 ? .user : .assistant, "m\($0)") }
        let context = ChatSessions.contextMessages(messages, maxMessages: 4)
        #expect(context.map(\.content) == ["m6", "m7", "m8", "m9"])
        #expect(context.first?.role == .user)
    }

    @Test("字数超限时从旧的开始丢，但至少留最后一条")
    func characterLimit() {
        let messages = [
            message(.user, String(repeating: "a", count: 50)),
            message(.assistant, String(repeating: "b", count: 50)),
            message(.user, String(repeating: "c", count: 200))
        ]
        let context = ChatSessions.contextMessages(messages, maxCharacters: 100)
        #expect(context.count == 1)
        #expect(context.first?.content.first == "c")
    }

    @Test("裁剪后以回复开头时丢掉开头的回复")
    func startsWithUser() {
        let messages = [
            message(.user, "问"), message(.assistant, "答"),
            message(.user, "再问"), message(.assistant, "再答")
        ]
        let context = ChatSessions.contextMessages(messages, maxMessages: 3)
        #expect(context.first?.role == .user)
        #expect(context.map(\.content) == ["再问", "再答"])
    }

    @Test("空历史得到空数组")
    func empty() {
        #expect(ChatSessions.contextMessages([]).isEmpty)
    }
}

@Suite("中断恢复")
struct ChatRecoveryTests {

    @Test("空内容且无失败标记的助手消息被标成失败")
    func marksEmptyReplyAsFailed() {
        let broken = ChatSession(messages: [
            message(.user, "问"), ChatMessage(role: .assistant, content: "")
        ])
        let recovered = ChatSessions.recoveringInterrupted(broken)
        #expect(recovered.messages[1].failure == "上次生成被中断")
        #expect(recovered.messages[0].failure == nil)
    }

    @Test("正常与已失败的消息保持原样")
    func leavesOthersAlone() {
        let healthy = ChatSession(messages: [
            message(.user, "问"), message(.assistant, "答"),
            ChatMessage(role: .assistant, content: "", failure: "超时")
        ])
        #expect(ChatSessions.recoveringInterrupted(healthy) == healthy)
    }
}
