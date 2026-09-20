// NoteStoreTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginNotes

@Suite("笔记存储")
@MainActor
struct NoteStoreTests {

    /// 一个应用过插件 schema 的内存库
    ///
    /// 内存库每个实例彼此独立：测存储不用碰磁盘，也不用清临时目录，
    /// 而且「重开一个 store 读同一个库」才是持久化真正被验证的地方。
    private func makeStorage() throws -> PluginStorage {
        let database = try SQLiteDatabase()
        try database.migrate(NotesPlugin.storageMigrations)
        return PluginStorage(pluginID: NotesPlugin.id, database: database)
    }

    @Test("新增笔记后能从库里读回")
    func addNoteRoundTrip() throws {
        let store = NoteStore(storage: try makeStorage())
        store.addNote(NoteItem(title: "标题", content: "正文", category: .todo))

        #expect(store.notes.count == 1)
        #expect(store.notes.first?.title == "标题")
        #expect(store.notes.first?.content == "正文")
        #expect(store.notes.first?.category == .todo)
    }

    @Test("重开 store 读同一个库仍能看到笔记与待办")
    func reopeningStoreSeesPersistedData() throws {
        let storage = try makeStorage()
        let writer = NoteStore(storage: storage)
        writer.addNote(NoteItem(title: "写进去的", content: "内容"))
        writer.addTodo(TodoItem(text: "待办一"))

        // 新实例的 init 直接读库 —— init 能读到，才说明上一实例真的落库了
        let reader = NoteStore(storage: storage)
        #expect(reader.notes.map(\.title) == ["写进去的"])
        #expect(reader.todos.map(\.text) == ["待办一"])
    }

    @Test("第二个 store 实例能看到第一个实例刚做的改动")
    func mutationIsVisibleToSecondStore() throws {
        let storage = try makeStorage()
        let store = NoteStore(storage: storage)
        let note = NoteItem(title: "共享库")
        store.addNote(note)

        let observer = NoteStore(storage: storage)
        #expect(observer.notes.count == 1)

        let todo = TodoItem(text: "共享待办")
        store.addTodo(todo)
        observer.load()
        #expect(observer.todos.map(\.text) == ["共享待办"])

        store.deleteNote(note.id)
        observer.load()
        #expect(observer.notes.isEmpty)
    }

    @Test("更新笔记是原地改写而不是新增一条")
    func updateNoteReplacesInPlace() throws {
        let storage = try makeStorage()
        let store = NoteStore(storage: storage)
        store.addNote(NoteItem(title: "旧标题", content: "旧正文"))

        var edited = try #require(store.notes.first)
        edited.title = "新标题"
        edited.content = "新正文"
        store.updateNote(edited)

        #expect(store.notes.count == 1)
        #expect(store.notes.first?.title == "新标题")
        // 库里也必须只有一条
        #expect(NoteStore(storage: storage).notes.map(\.title) == ["新标题"])
    }

    @Test("删除笔记在内存与库里同时生效")
    func deleteNoteRemovesFromDatabase() throws {
        let storage = try makeStorage()
        let store = NoteStore(storage: storage)
        store.addNote(NoteItem(title: "保留"))
        let doomed = NoteItem(title: "删除")
        store.addNote(doomed)

        store.deleteNote(doomed.id)

        #expect(store.notes.map(\.title) == ["保留"])
        #expect(NoteStore(storage: storage).notes.map(\.title) == ["保留"])
    }

    @Test("待办可以切换完成状态，且状态会落库")
    func toggleTodoPersists() throws {
        let storage = try makeStorage()
        let store = NoteStore(storage: storage)
        let todo = TodoItem(text: "跑测试")
        store.addTodo(todo)

        store.toggleTodo(todo.id)
        #expect(store.todos.first?.isCompleted == true)
        #expect(NoteStore(storage: storage).todos.first?.isCompleted == true)

        store.toggleTodo(todo.id)
        #expect(store.todos.first?.isCompleted == false)
    }

    @Test("删除待办在内存与库里同时生效")
    func deleteTodoRemovesFromDatabase() throws {
        let storage = try makeStorage()
        let store = NoteStore(storage: storage)
        let doomed = TodoItem(text: "删除我")
        store.addTodo(doomed)
        store.addTodo(TodoItem(text: "留下"))

        store.deleteTodo(doomed.id)

        #expect(store.todos.map(\.text) == ["留下"])
        #expect(NoteStore(storage: storage).todos.map(\.text) == ["留下"])
    }

    @Test("笔记最新在前，待办按添加顺序")
    func orderingIsStable() throws {
        let store = NoteStore(storage: try makeStorage())
        store.addNote(NoteItem(title: "第一条"))
        store.addNote(NoteItem(title: "第二条"))
        // 同一瞬间创建的两条也要有确定顺序，所以排序带 rowid 作为次序判据
        #expect(store.notes.map(\.title) == ["第二条", "第一条"])

        store.addTodo(TodoItem(text: "先"))
        store.addTodo(TodoItem(text: "后"))
        #expect(store.todos.map(\.text) == ["先", "后"])
    }

    @Test("重建出的笔记保留原始 id 与时间戳，不会每次读取都漂移")
    func reconstructionKeepsIdentity() throws {
        let storage = try makeStorage()
        let note = NoteItem(title: "身份", content: "不能变")
        NoteStore(storage: storage).addNote(note)

        let loaded = try #require(NoteStore(storage: storage).notes.first)
        #expect(loaded.id == note.id)
        #expect(abs(loaded.createdAt.timeIntervalSince(note.createdAt)) < 0.001)
        #expect(abs(loaded.updatedAt.timeIntervalSince(note.updatedAt)) < 0.001)
    }

    @Test("搜索忽略大小写，空查询返回全部")
    func searchIsCaseInsensitive() throws {
        let store = NoteStore(storage: try makeStorage())
        store.addNote(NoteItem(title: "Hello World", content: "正文"))
        store.addNote(NoteItem(title: "别的内容"))

        #expect(store.search("").count == 2)
        #expect(store.search("hello").count == 1)
        #expect(store.search("HELLO").count == 1)
        #expect(store.search("正文").count == 1)
        #expect(store.search("不存在的关键词").isEmpty)
    }
}
