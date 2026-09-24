// NoteStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Synchronization

/// 搜索用的笔记快照
///
/// 小写形态在刷新时算一次：搜索要脱离主 actor（见 `dynamicSearch` 的说明），
/// 而每次按键都重新 `lowercased()` 几百条笔记是把开销放在了热路径上。
struct NoteSearchSnapshot: Sendable {
    let id: UUID
    let title: String
    let preview: String
    private let loweredTitle: String
    private let loweredContent: String

    init(id: UUID, title: String, content: String, preview: String) {
        self.id = id
        self.title = title
        self.preview = preview
        self.loweredTitle = title.lowercased()
        self.loweredContent = content.lowercased()
    }

    /// 标题或正文包含关键词
    func matches(_ loweredQuery: String) -> Bool {
        loweredTitle.contains(loweredQuery) || loweredContent.contains(loweredQuery)
    }
}

/// 笔记存储
///
/// 笔记与待办各一张表，一个用户动作一条语句 —— 旧版把整个数组编码成 JSON 重写文件，
/// 一次改动就要重写全部内容，且任何一步失败都会丢掉全部笔记（旧代码里到处是 `try?`，
/// 失败连一条日志都没有）。
///
/// 内存缓存保留给 SwiftUI 直接读，但数据库才是真相：写操作失败时缓存回到库里的
/// 实际状态，而不是继续显示一个没落库的假象。
@MainActor
@Observable
final class NoteStore {

    private(set) var notes: [NoteItem] = []
    private(set) var todos: [TodoItem] = []

    private let log = QuickLog.plugin(NotesPlugin.id)

    /// 存储句柄
    private let storage: PluginStorage

    /// 搜索快照
    ///
    /// 主 actor 上每次 load/reload 后重建，`nonisolated` 的 `search` 直接读它 ——
    /// 这样搜索不必回到主 actor 排队。用 `Mutex` 而不是假设「主 actor 写、
    /// 后台读」天然安全：两者之间没有 happens-before 关系。
    private let searchSnapshot = Mutex<[NoteSearchSnapshot]>([])

    /// 初始化并加载
    ///
    /// 同步加载：数据库就在本地，一次查询是微秒级，没有必要把它变成异步再让视图等一轮。
    /// - Parameter storage: 由 AppCore 注入的存储句柄（测试传内存库）
    init(storage: PluginStorage) {
        self.storage = storage
        load()
    }

    // MARK: - 查询

    /// 按关键词过滤笔记，可脱离主 actor 调用
    nonisolated func search(_ query: String) -> [NoteSearchSnapshot] {
        searchSnapshot.withLock { snapshot in
            guard !query.isEmpty else { return snapshot }
            let lowered = query.lowercased()
            return snapshot.filter { $0.matches(lowered) }
        }
    }

    // MARK: - 增删改

    func addNote(_ note: NoteItem) {
        do {
            try storage.database.execute(Self.insertNoteSQL, Self.noteBindings(note))
        } catch {
            log.error("笔记写入失败：\(error)")
        }
        reloadNotes()
    }

    func updateNote(_ note: NoteItem) {
        do {
            try storage.database.execute(
                """
                UPDATE notes
                SET title = ?, content = ?, category = ?, is_pinned = ?, updated_at = ?
                WHERE id = ?
                """,
                [
                    .text(note.title),
                    .text(note.content),
                    .text(note.category.rawValue),
                    .bool(note.isPinned),
                    .date(note.updatedAt),
                    .text(note.id.uuidString)
                ])
        } catch {
            log.error("笔记更新失败：\(error)")
        }
        reloadNotes()
    }

    func deleteNote(_ id: UUID) {
        do {
            try storage.database.execute(
                "DELETE FROM notes WHERE id = ?", [.text(id.uuidString)])
        } catch {
            log.error("笔记删除失败：\(error)")
        }
        reloadNotes()
    }

    func addTodo(_ todo: TodoItem) {
        do {
            try storage.database.execute(
                """
                INSERT INTO todos (id, text, is_completed, created_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    text = excluded.text,
                    is_completed = excluded.is_completed
                """,
                [
                    .text(todo.id.uuidString),
                    .text(todo.text),
                    .bool(todo.isCompleted),
                    .date(todo.createdAt)
                ])
        } catch {
            log.error("待办写入失败：\(error)")
        }
        reloadTodos()
    }

    func toggleTodo(_ id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        let isCompleted = !todos[index].isCompleted
        do {
            try storage.database.execute(
                "UPDATE todos SET is_completed = ? WHERE id = ?",
                [.bool(isCompleted), .text(id.uuidString)])
        } catch {
            log.error("待办状态更新失败：\(error)")
        }
        reloadTodos()
    }

    func deleteTodo(_ id: UUID) {
        do {
            try storage.database.execute(
                "DELETE FROM todos WHERE id = ?", [.text(id.uuidString)])
        } catch {
            log.error("待办删除失败：\(error)")
        }
        reloadTodos()
    }

    // MARK: - 持久化

    /// 从数据库重新读回内存缓存
    func load() {
        do {
            notes = try Self.fetchNotes(from: storage.database)
            todos = try Self.fetchTodos(from: storage.database)
            rebuildSearchSnapshot()
            log.info(
                """
                笔记已加载：\(self.notes.count, privacy: .public) 条笔记、\
                \(self.todos.count, privacy: .public) 条待办
                """)
        } catch {
            // 读不出来不能让插件起不来：记一条 error，按空数据继续
            log.error("笔记读取失败，已按空数据继续：\(error)")
            notes = []
            todos = []
            rebuildSearchSnapshot()
        }
    }

    /// 把内存缓存刷成数据库里的真实内容
    ///
    /// 平时的改动已经逐条写过了，这里只是确保退出前界面与库里一致。
    func save() {
        reloadNotes()
        reloadTodos()
    }

    /// 按数据库里的真实内容重排笔记缓存
    private func reloadNotes() {
        do {
            notes = try Self.fetchNotes(from: storage.database)
        } catch {
            log.error("笔记缓存刷新失败：\(error)")
        }
        rebuildSearchSnapshot()
    }

    /// 重建搜索快照
    ///
    /// 唯一修改快照的地方。放在所有会改变 `notes` 的路径末尾，「搜索能读到刚写的
    /// 笔记」才是可推理的，而不是依赖调用顺序。
    private func rebuildSearchSnapshot() {
        let snapshot = notes.map {
            NoteSearchSnapshot(
                id: $0.id, title: $0.title, content: $0.content, preview: $0.preview)
        }
        searchSnapshot.withLock { $0 = snapshot }
    }

    /// 按数据库里的真实内容重排待办缓存
    private func reloadTodos() {
        do {
            todos = try Self.fetchTodos(from: storage.database)
        } catch {
            log.error("待办缓存刷新失败：\(error)")
        }
    }

    // MARK: - SQL 片段

    /// 笔记按创建时间倒序
    ///
    /// `rowid` 是次序的最终判据：同一毫秒内创建的两条笔记时间戳可能完全相等，
    /// 只按时间排序会让它们的相对顺序随查询计划变化 —— 界面上的顺序就不稳定了。
    private static let selectNotesSQL = """
        SELECT id, title, content, category, is_pinned, created_at, updated_at
        FROM notes
        ORDER BY created_at DESC, rowid DESC
        """

    /// 待办按创建时间正序（添加是往末尾追加）
    private static let selectTodosSQL = """
        SELECT id, text, is_completed, created_at
        FROM todos
        ORDER BY created_at ASC, rowid ASC
        """

    private static let insertNoteSQL = """
        INSERT INTO notes (id, title, content, category, is_pinned, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            content = excluded.content,
            category = excluded.category,
            is_pinned = excluded.is_pinned,
            updated_at = excluded.updated_at
        """

    private static func noteBindings(_ note: NoteItem) -> [SQLiteValue] {
        [
            .text(note.id.uuidString),
            .text(note.title),
            .text(note.content),
            .text(note.category.rawValue),
            .bool(note.isPinned),
            .date(note.createdAt),
            .date(note.updatedAt)
        ]
    }

    private static func fetchNotes(from database: SQLiteDatabase) throws -> [NoteItem] {
        try database.query(selectNotesSQL).compactMap(note(from:))
    }

    private static func fetchTodos(from database: SQLiteDatabase) throws -> [TodoItem] {
        try database.query(selectTodosSQL).compactMap(todo(from:))
    }

    /// 一行 → 一条笔记
    private static func note(from row: SQLiteRow) -> NoteItem? {
        guard let idText = row.text("id"), let id = UUID(uuidString: idText),
            let categoryText = row.text("category"),
            let category = NoteCategory(rawValue: categoryText)
        else { return nil }

        return NoteItem(
            id: id,
            title: row.text("title") ?? "",
            content: row.text("content") ?? "",
            category: category,
            isPinned: row.bool("is_pinned") ?? false,
            createdAt: row.date("created_at") ?? Date(),
            updatedAt: row.date("updated_at") ?? Date())
    }

    /// 一行 → 一条待办
    private static func todo(from row: SQLiteRow) -> TodoItem? {
        guard let idText = row.text("id"), let id = UUID(uuidString: idText) else { return nil }

        return TodoItem(
            id: id,
            text: row.text("text") ?? "",
            isCompleted: row.bool("is_completed") ?? false,
            createdAt: row.date("created_at") ?? Date())
    }
}
