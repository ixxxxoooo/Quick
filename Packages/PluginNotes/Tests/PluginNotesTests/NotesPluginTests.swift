// NotesPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginNotes

@MainActor
@Suite("笔记插件契约")
struct NotesPluginTests {

    private func makePlugin(with note: NoteItem) throws -> NotesPlugin {
        let database = try SQLiteDatabase()
        try database.migrate(NotesPlugin.storageMigrations)
        let storage = PluginStorage(pluginID: NotesPlugin.id, database: database)
        let store = NoteStore(storage: storage)
        store.addNote(note)
        return NotesPlugin(storage: storage)
    }

    @Test("命中触发词时返回匹配笔记")
    func searchItemsReturnsNotes() async throws {
        let plugin = try makePlugin(with: NoteItem(title: "会议记录", content: "要点"))
        let items = await plugin.dynamicSearch(query: "笔记")

        #expect(items.count == 1)
        #expect(items.first?.pluginID == NotesPlugin.id)
        #expect(items.first?.title == "会议记录")
    }

    @Test("搜索结果执行 action 会发布带 noteID 的 NavigateEvent")
    func searchResultNavigatesWithNoteID() async throws {
        let note = NoteItem(title: "待打开", content: "正文")
        let plugin = try makePlugin(with: note)
        let item = try #require(await plugin.dynamicSearch(query: "memo").first)

        var navigated: [NavigateEvent] = []
        let subscription = EventBus.shared.on(NavigateEvent.self) { navigated.append($0) }
        defer { subscription.cancel() }

        item.action()
        #expect(navigated.count == 1)
        #expect(navigated.first?.pluginID == NotesPlugin.id)
        #expect(navigated.first?.context["noteID"] == note.id.uuidString)
    }

    @Test("未命中触发词时不返回结果")
    func unrelatedQueryReturnsNothing() async throws {
        let plugin = try makePlugin(with: NoteItem(title: "x", content: "y"))
        #expect(await plugin.dynamicSearch(query: "天气").isEmpty)
    }
}
