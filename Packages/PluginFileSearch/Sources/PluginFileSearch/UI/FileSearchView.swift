// FileSearchView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 文件搜索插件视图
struct FileSearchView: View {

    let session: FileSearchSession

    @State private var searchText = ""
    @State private var results: [FileSearchSession.FileResult] = []

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                TextField("搜索文件…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.searchField)
                    .onSubmit {
                        Task {
                            results = await session.search(query: searchText)
                        }
                    }
            }
            .padding(DesignTokens.Spacing.xl)

            Divider().opacity(0.3)

            // 结果列表
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xxs) {
                    ForEach(results) { file in
                        FileResultRow(file: file)
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }
        }
        .onChange(of: searchText) { _, newValue in
            guard !newValue.isEmpty else {
                results = []
                return
            }
            Task {
                results = await session.search(query: newValue)
            }
        }
    }
}

/// 文件搜索结果行
struct FileResultRow: View {
    let file: FileSearchSession.FileResult

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: file.icon)
                .font(.system(size: 16))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(DesignTokens.Typography.rowTitle)
                    .lineLimit(1)
                Text(file.path)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                .fill(isHovered ? DesignTokens.Colors.rowHover : .clear)
        }
        .onHover { isHovered = $0 }
        .onTapGesture {
            NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
            EventBus.shared.post(HidePaletteEvent())
        }
        .contentShape(Rectangle())
    }
}
