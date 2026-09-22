// SnippetsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 文本片段管理视图
struct SnippetsView: View {

    let store: SnippetStore
    @State private var selectedID: UUID?
    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var editContent = ""
    @State private var editKeyword = ""

    var body: some View {
        HStack(spacing: 0) {
            // 左侧列表
            VStack(spacing: 0) {
                HStack {
                    Text("片段列表")
                        .font(DesignTokens.Typography.sectionHeader)
                    Spacer()
                    Button {
                        editTitle = ""
                        editContent = ""
                        editKeyword = ""
                        isEditing = true
                        selectedID = nil
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
                .padding(DesignTokens.Spacing.xl)

                ScrollView {
                    LazyVStack(spacing: DesignTokens.Spacing.xxs) {
                        ForEach(store.snippets) { snippet in
                            SnippetRow(snippet: snippet, isSelected: selectedID == snippet.id)
                                .onTapGesture {
                                    selectedID = snippet.id
                                    editTitle = snippet.title
                                    editContent = snippet.content
                                    editKeyword = snippet.keyword ?? ""
                                    isEditing = true
                                }
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                }
            }
            .frame(width: 250)

            Divider().opacity(0.3)

            // 右侧编辑器
            if isEditing {
                VStack(spacing: DesignTokens.Spacing.md) {
                    TextField("标题", text: $editTitle)
                        .textFieldStyle(.plain)
                        .font(DesignTokens.Typography.panelTitle)
                        .padding(DesignTokens.Spacing.md)

                    TextField("触发关键词（可选）", text: $editKeyword)
                        .textFieldStyle(.plain)
                        .font(DesignTokens.Typography.rowTrailing)
                        .padding(DesignTokens.Spacing.md)

                    TextEditor(text: $editContent)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                        .padding(DesignTokens.Spacing.md)
                        .background(DesignTokens.Colors.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))

                    HStack {
                        Spacer()
                        Button("保存") {
                            saveSnippet()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(DesignTokens.Spacing.xl)
            } else {
                Text("选择或创建一个片段")
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func saveSnippet() {
        if let id = selectedID, var existing = store.snippets.first(where: { $0.id == id }) {
            existing.title = editTitle
            existing.content = editContent
            existing.keyword = editKeyword.isEmpty ? nil : editKeyword
            store.update(existing)
        } else {
            let snippet = Snippet(
                title: editTitle,
                content: editContent,
                keyword: editKeyword.isEmpty ? nil : editKeyword
            )
            store.add(snippet)
            selectedID = snippet.id
        }
    }
}

/// 片段行视图
struct SnippetRow: View {
    let snippet: Snippet
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snippet.title)
                .font(DesignTokens.Typography.rowTitle)
                .lineLimit(1)
            Text(snippet.preview)
                .font(DesignTokens.Typography.keyCap)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                .fill(isSelected ? DesignTokens.Colors.selection : .clear)
        }
        .contentShape(Rectangle())
    }
}
