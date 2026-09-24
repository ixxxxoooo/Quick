// NotesPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 笔记与便签插件
///
/// 轻量笔记 + 桌面便签 + 待办清单。
/// 合并 Fasty 的 memo、sticky-notes、todo-list 功能。
@MainActor
public final class NotesPlugin: QuickPlugin, PluginViewProviding, PluginSettingsProviding {

    public static let id = "notes"
    public static let name = "笔记"
    public static let icon = "note.text"
    public static let description = "轻量级便签与待办备忘录，支持极简富文本与 Markdown 记录，编辑即时自动保存且本地安全存储。"
    public static let triggerWords = ["备忘录", "memo", "note", "笔记", "便签"]

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "notes.new", pluginID: id, pluginName: name, title: "新建笔记",
                subtitle: "创建一条新笔记", keywords: ["新建笔记"], icon: "square.and.pencil"),
            CommandDescriptor(
                id: "notes.todo", pluginID: id, pluginName: name, title: "待办",
                subtitle: "打开待办列表", keywords: ["待办", "todo"], icon: "checklist")
        ]
    }

    public var isEnabled = true

    private let log = QuickLog.plugin(NotesPlugin.id)

    private let store: NoteStore

    /// - Parameter storage: 由 AppCore 注入的存储句柄
    public init(storage: PluginStorage) {
        self.store = NoteStore(storage: storage)
    }

    // MARK: - 存储 schema

    /// 笔记与待办两张表
    ///
    /// 表结构归插件所有：宿主只负责把它跑一遍，不读这两张表。
    /// 排序索引对应界面顺序 —— 笔记最新在前，待办按添加顺序。
    public static var storageMigrations: [SQLiteMigration] {
        [
            SQLiteMigration(
                id: "notes.items",
                statements: [
                    """
                    CREATE TABLE IF NOT EXISTS notes (
                        id TEXT PRIMARY KEY,
                        title TEXT NOT NULL DEFAULT '',
                        content TEXT NOT NULL DEFAULT '',
                        category TEXT NOT NULL,
                        is_pinned INTEGER NOT NULL DEFAULT 0,
                        created_at REAL NOT NULL,
                        updated_at REAL NOT NULL
                    )
                    """,
                    "CREATE INDEX IF NOT EXISTS idx_notes_created ON notes(created_at DESC)"
                ]),
            SQLiteMigration(
                id: "notes.todos",
                statements: [
                    """
                    CREATE TABLE IF NOT EXISTS todos (
                        id TEXT PRIMARY KEY,
                        text TEXT NOT NULL DEFAULT '',
                        is_completed INTEGER NOT NULL DEFAULT 0,
                        created_at REAL NOT NULL
                    )
                    """,
                    "CREATE INDEX IF NOT EXISTS idx_todos_created ON todos(created_at ASC)"
                ])
        ]
    }

    public func accepts(query: String) -> Bool {
        query.matchesAnyTrigger(Self.triggerWords)
    }

    public nonisolated func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }

        // 用整词匹配而不是 contains：否则 memory 会误命中 memo
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }

        // 拿剥离触发词后的词去搜；只剩触发词时为空串，表示列出全部笔记。
        // 走的是 store 的搜索快照，不必回到主 actor。
        let keyword = query.removingTrigger(Self.triggerWords)
        let notes = store.search(keyword)
        return notes.prefix(5).map { note in
            SearchableItem(
                id: "notes.\(note.id)",
                pluginID: Self.id,
                title: note.title,
                subtitle: note.preview,
                icon: "note.text",
                relevance: 0.5,
                action: {
                    EventBus.shared.post(
                        NavigateEvent(pluginID: Self.id, context: ["noteID": note.id.uuidString]))
                }
            )
        }
    }

    public func makeView() -> AnyView {
        AnyView(NotesView(store: store))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(NotesSettingsView())
    }

    public func activate() {
        // 加载已在 init 里完成，这里只汇报
        log.notice(
            """
            插件已激活：加载 \(self.store.notes.count, privacy: .public) 条笔记、\
            \(self.store.todos.count, privacy: .public) 条待办
            """)
    }

    public func deactivate() {
        store.save()
        log.notice("插件已停用，笔记与待办已落盘")
    }
}
