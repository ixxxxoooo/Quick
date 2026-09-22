// NotesView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 笔记插件视图
struct NotesView: View {

    let store: NoteStore
    @State private var selectedID: UUID?
    @State private var editTitle = ""
    @State private var editContent = ""
    @State private var newTodo = ""
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // 标签切换
            Picker("", selection: $selectedTab) {
                Text("笔记").tag(0)
                Text("待办").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(DesignTokens.Spacing.md)

            if selectedTab == 0 {
                notesTab
            } else {
                todoTab
            }
        }
    }

    // MARK: - 笔记标签

    private var notesTab: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Button {
                    let note = NoteItem(title: "新笔记")
                    store.addNote(note)
                    selectedID = note.id
                    editTitle = note.title
                    editContent = note.content
                } label: {
                    Label("新建", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(DesignTokens.Spacing.md)

                ScrollView {
                    LazyVStack(spacing: DesignTokens.Spacing.xxs) {
                        ForEach(store.notes) { note in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title).font(DesignTokens.Typography.rowTitle).lineLimit(1)
                                Text(note.preview).font(DesignTokens.Typography.keyCap).foregroundStyle(
                                    DesignTokens.Colors.textTertiary
                                ).lineLimit(1)
                            }
                            .padding(DesignTokens.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                                    .fill(selectedID == note.id ? DesignTokens.Colors.selection : .clear)
                            }
                            .onTapGesture {
                                selectedID = note.id
                                editTitle = note.title
                                editContent = note.content
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                }
            }
            .frame(width: 200)

            Divider().opacity(0.3)

            if selectedID != nil {
                VStack(spacing: DesignTokens.Spacing.md) {
                    TextField("标题", text: $editTitle)
                        .textFieldStyle(.plain)
                        .font(DesignTokens.Typography.panelTitle)
                    TextEditor(text: $editContent)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                    HStack {
                        Spacer()
                        Button("保存") {
                            guard var note = store.notes.first(where: { $0.id == selectedID }) else { return }
                            note.title = editTitle
                            note.content = editContent
                            store.updateNote(note)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(DesignTokens.Spacing.xl)
            } else {
                Text("选择或创建一个笔记")
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - 待办标签

    private var todoTab: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            HStack {
                TextField("添加待办…", text: $newTodo)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        guard !newTodo.isEmpty else { return }
                        store.addTodo(TodoItem(text: newTodo))
                        newTodo = ""
                    }
                Button {
                    guard !newTodo.isEmpty else { return }
                    store.addTodo(TodoItem(text: newTodo))
                    newTodo = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.top, DesignTokens.Spacing.md)

            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(store.todos) { todo in
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(
                                    todo.isCompleted
                                        ? DesignTokens.Colors.success : DesignTokens.Colors.textTertiary
                                )
                                .onTapGesture { store.toggleTodo(todo.id) }
                            Text(todo.text)
                                .strikethrough(todo.isCompleted)
                                .foregroundStyle(
                                    todo.isCompleted
                                        ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, DesignTokens.Spacing.xl)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                    }
                }
            }
        }
    }
}
