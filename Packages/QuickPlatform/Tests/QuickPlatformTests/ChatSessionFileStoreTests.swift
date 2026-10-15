// ChatSessionFileStoreTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import QuickPlatform

private func makeStore() -> ChatSessionFileStore {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ChatSessionFileStoreTests-\(UUID().uuidString)", isDirectory: true)
    return ChatSessionFileStore(directory: directory)
}

private func sample(_ title: String = "标题") -> ChatSession {
    ChatSession(
        title: title,
        isPinned: true,
        model: AIModelRef(providerID: "p", model: "m"),
        messages: [
            ChatMessage(role: .user, content: "问"),
            ChatMessage(role: .assistant, content: "答", model: "m"),
            ChatMessage(role: .assistant, content: "", failure: "超时")
        ])
}

@Suite("ChatSessionFileStore")
struct ChatSessionFileStoreTests {

    @Test("目录还不存在时读出空列表")
    func loadFromMissingDirectory() {
        #expect(makeStore().loadAll().isEmpty)
    }

    @Test("保存后能原样读回，包含模型、置顶与失败信息")
    func roundTrip() throws {
        let store = makeStore()
        let session = sample()
        try store.save(session)
        let loaded = try #require(store.loadAll().first)
        #expect(loaded.id == session.id)
        #expect(loaded.title == "标题")
        #expect(loaded.isPinned)
        #expect(loaded.model == session.model)
        #expect(loaded.messages.map(\.content) == ["问", "答", ""])
        #expect(loaded.messages.last?.failure == "超时")
        // ISO8601 只到秒，往返会丢掉亚秒；同一秒内即视为相等
        #expect(abs(loaded.createdAt.timeIntervalSince(session.createdAt)) < 1)
        try? FileManager.default.removeItem(at: store.directory)
    }

    @Test("同一个会话再次保存是覆盖，不是新增")
    func saveOverwrites() throws {
        let store = makeStore()
        var session = sample()
        try store.save(session)
        session.title = "改过的"
        try store.save(session)
        let all = store.loadAll()
        #expect(all.count == 1)
        #expect(all.first?.title == "改过的")
        try? FileManager.default.removeItem(at: store.directory)
    }

    @Test("删除只影响目标会话")
    func deleteOne() throws {
        let store = makeStore()
        let keep = sample("留")
        let drop = sample("删")
        try store.save(keep)
        try store.save(drop)
        store.delete(id: drop.id)
        #expect(store.loadAll().map(\.title) == ["留"])
        try? FileManager.default.removeItem(at: store.directory)
    }

    @Test("损坏的文件被跳过，其余会话照常读出")
    func corruptedFileIsSkipped() throws {
        let store = makeStore()
        try store.save(sample("好的"))
        try Data("{坏了".utf8).write(
            to: store.directory.appendingPathComponent("\(UUID().uuidString).json"))
        #expect(store.loadAll().map(\.title) == ["好的"])
        try? FileManager.default.removeItem(at: store.directory)
    }

    @Test("清空会删掉全部会话")
    func deleteAll() throws {
        let store = makeStore()
        try store.save(sample("a"))
        try store.save(sample("b"))
        store.deleteAll()
        #expect(store.loadAll().isEmpty)
    }
}
