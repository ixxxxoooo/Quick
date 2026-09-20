// NoteStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickPlatform

/// 笔记存储
@MainActor
@Observable
final class NoteStore {

    private(set) var notes: [NoteItem] = []
    private(set) var todos: [TodoItem] = []

    private var notesURL: URL {
        AppPaths.pluginData("notes").appendingPathComponent("notes.json")
    }
    private var todosURL: URL {
        AppPaths.pluginData("notes").appendingPathComponent("todos.json")
    }

    func search(_ query: String) -> [NoteItem] {
        guard !query.isEmpty else { return notes }
        let lower = query.lowercased()
        return notes.filter {
            $0.title.lowercased().contains(lower) || $0.content.lowercased().contains(lower)
        }
    }

    func addNote(_ note: NoteItem) {
        notes.insert(note, at: 0)
        save()
    }

    func updateNote(_ note: NoteItem) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[i] = note
        save()
    }

    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    func addTodo(_ todo: TodoItem) {
        todos.append(todo)
        save()
    }

    func toggleTodo(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].isCompleted.toggle()
        save()
    }

    func deleteTodo(_ id: UUID) {
        todos.removeAll { $0.id == id }
        save()
    }

    func load() {
        if let d = try? Data(contentsOf: notesURL),
            let n = try? JSONDecoder().decode([NoteItem].self, from: d)
        {
            notes = n
        }
        if let d = try? Data(contentsOf: todosURL),
            let t = try? JSONDecoder().decode([TodoItem].self, from: d)
        {
            todos = t
        }
    }

    func save() {
        if let d = try? JSONEncoder().encode(notes) { try? d.write(to: notesURL) }
        if let d = try? JSONEncoder().encode(todos) { try? d.write(to: todosURL) }
    }
}
