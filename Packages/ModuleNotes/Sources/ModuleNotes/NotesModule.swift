// NotesModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 笔记与便签模块
///
/// 轻量笔记 + 桌面便签 + 待办清单。
/// 合并 Fasty 的 memo、sticky-notes、todo-list 功能。
@MainActor
public final class NotesModule: QuickModule {

    public static let id = "notes"
    public static let name = "笔记"
    public static let icon = "note.text"

    public var isEnabled = true

    private let log = QuickLog.module(NotesModule.id)

    private let store = NoteStore()

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        let triggers = ["笔记", "备忘", "note", "memo", "便签", "待办", "todo"]
        // 用整词匹配而不是 contains：否则 memory 会误命中 memo
        guard query.matchesAnyTrigger(triggers) else { return [] }

        // 拿剥离触发词后的词去搜；只剩触发词时为空串，表示列出全部笔记
        let keyword = query.removingTrigger(triggers)
        let notes = store.search(keyword)
        return notes.prefix(5).map { note in
            SearchableItem(
                id: "notes.\(note.id)",
                moduleID: Self.id,
                title: note.title,
                subtitle: note.preview,
                icon: "note.text",
                relevance: 0.5,
                action: {}
            )
        }
    }

    public func makeView() -> AnyView {
        AnyView(NotesView(store: store))
    }

    public func activate() {
        store.load()
        log.notice(
            """
            模块已激活：加载 \(self.store.notes.count, privacy: .public) 条笔记、\
            \(self.store.todos.count, privacy: .public) 条待办
            """)
    }

    public func deactivate() {
        store.save()
        log.notice("模块已停用，笔记与待办已落盘")
    }
}
