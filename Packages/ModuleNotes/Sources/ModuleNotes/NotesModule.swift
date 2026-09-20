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

    private let store = NoteStore()

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        let triggers = ["笔记", "备忘", "note", "memo", "便签", "待办", "todo"]
        guard triggers.contains(where: { query.lowercased().contains($0) }) else { return [] }

        let notes = store.search(query)
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
    }

    public func deactivate() {
        store.save()
    }
}
