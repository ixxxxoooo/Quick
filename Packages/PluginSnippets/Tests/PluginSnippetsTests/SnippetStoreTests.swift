// SnippetStoreTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginSnippets

@Suite("片段存储")
@MainActor
struct SnippetStoreTests {

    /// 一个应用过插件 schema 的内存库
    ///
    /// 内存库每个实例彼此独立：测存储不用碰磁盘，也不用清临时目录，
    /// 而且「重开一个 store 读同一个库」才是持久化真正被验证的地方。
    private func makeStorage() throws -> PluginStorage {
        let database = try SQLiteDatabase()
        try database.migrate(SnippetsPlugin.storageMigrations)
        return PluginStorage(pluginID: SnippetsPlugin.id, database: database)
    }

    @Test("新增片段后能从库里读回，可选字段保持为空")
    func addRoundTrip() throws {
        let store = SnippetStore(storage: try makeStorage())
        store.add(Snippet(title: "标题", content: "内容", keyword: "sig", category: "邮件"))

        #expect(store.snippets.count == 1)
        let snippet = try #require(store.snippets.first)
        #expect(snippet.title == "标题")
        #expect(snippet.content == "内容")
        #expect(snippet.keyword == "sig")
        #expect(snippet.category == "邮件")

        store.add(Snippet(title: "无关键词", content: "内容"))
        let bare = try #require(store.snippets.first { $0.title == "无关键词" })
        #expect(bare.keyword == nil)
        #expect(bare.category == nil)
    }

    @Test("重开 store 读同一个库仍能看到片段")
    func reopeningStoreSeesPersistedData() throws {
        let storage = try makeStorage()
        SnippetStore(storage: storage).add(Snippet(title: "写进去的", content: "内容"))

        // 新实例的 init 直接读库 —— init 能读到，才说明上一实例真的落库了
        let reader = SnippetStore(storage: storage)
        #expect(reader.snippets.map(\.title) == ["写进去的"])
    }

    @Test("第二个 store 实例能看到第一个实例刚做的改动")
    func mutationIsVisibleToSecondStore() throws {
        let storage = try makeStorage()
        let store = SnippetStore(storage: storage)
        let snippet = Snippet(title: "共享库", content: "内容")
        store.add(snippet)

        let observer = SnippetStore(storage: storage)
        #expect(observer.snippets.count == 1)

        store.remove(snippet.id)
        observer.load()
        #expect(observer.snippets.isEmpty)
    }

    @Test("更新片段是原地改写而不是新增一条")
    func updateReplacesInPlace() throws {
        let storage = try makeStorage()
        let store = SnippetStore(storage: storage)
        store.add(Snippet(title: "旧标题", content: "旧内容"))

        var edited = try #require(store.snippets.first)
        edited.title = "新标题"
        edited.content = "新内容"
        edited.keyword = "new"
        store.update(edited)

        #expect(store.snippets.count == 1)
        let persisted = try #require(SnippetStore(storage: storage).snippets.first)
        #expect(persisted.title == "新标题")
        #expect(persisted.keyword == "new")
    }

    @Test("删除片段在内存与库里同时生效")
    func removeRemovesFromDatabase() throws {
        let storage = try makeStorage()
        let store = SnippetStore(storage: storage)
        let doomed = Snippet(title: "删除", content: "内容")
        store.add(doomed)
        store.add(Snippet(title: "保留", content: "内容"))

        store.remove(doomed.id)

        #expect(store.snippets.map(\.title) == ["保留"])
        #expect(SnippetStore(storage: storage).snippets.map(\.title) == ["保留"])
    }

    @Test("最新添加的片段排在最前")
    func newestComesFirst() throws {
        let store = SnippetStore(storage: try makeStorage())
        store.add(Snippet(title: "第一条", content: "内容"))
        store.add(Snippet(title: "第二条", content: "内容"))
        // 同一瞬间创建的两条也要有确定顺序，所以排序带 rowid 作为次序判据
        #expect(store.snippets.map(\.title) == ["第二条", "第一条"])
    }

    @Test("重建出的片段保留原始 id 与时间戳")
    func reconstructionKeepsIdentity() throws {
        let storage = try makeStorage()
        let snippet = Snippet(title: "身份", content: "不能变")
        SnippetStore(storage: storage).add(snippet)

        let loaded = try #require(SnippetStore(storage: storage).snippets.first)
        #expect(loaded.id == snippet.id)
        #expect(abs(loaded.createdAt.timeIntervalSince(snippet.createdAt)) < 0.001)
    }

    @Test("搜索命中标题、关键词与内容，忽略大小写")
    func searchIsCaseInsensitive() throws {
        let store = SnippetStore(storage: try makeStorage())
        store.add(Snippet(title: "Hello", content: "正文"))
        store.add(Snippet(title: "别的内容", content: "text", keyword: "sig"))

        #expect(store.search("").count == 2)
        #expect(store.search("hello").count == 1)
        #expect(store.search("SIG").count == 1)
        #expect(store.search("正文").count == 1)
        #expect(store.search("不存在的关键词").isEmpty)
    }
}
