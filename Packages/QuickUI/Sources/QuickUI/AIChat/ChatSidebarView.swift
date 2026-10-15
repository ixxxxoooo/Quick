// ChatSidebarView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 会话侧栏：搜索、新建、按时间分组的会话列表
struct ChatSidebarView: View {

    let controller: AIChatController
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            list
        }
        .onChange(of: controller.filterFocusToken) { _, _ in filterFocused = true }
    }

    // MARK: - 工具条

    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(DesignTokens.Typography.compactIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                TextField(
                    "搜索对话",
                    text: Binding(
                        get: { controller.sidebarFilter },
                        set: { controller.sidebarFilter = $0 })
                )
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.rowTrailing)
                .focused($filterFocused)
                // 搜索框里回车：打开第一个命中的会话并回到输入框
                .onSubmit {
                    if let first = controller.visibleOrder.first { controller.select(first) }
                    filterFocused = false
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(height: DesignTokens.Size.aiChatRowHeight)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                    .fill(DesignTokens.Colors.controlSurface.opacity(DesignTokens.Opacity.controlSurfaceDim))
            )

            Button {
                controller.newSession()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(DesignTokens.Typography.headerButtonMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(
                        width: DesignTokens.Size.aiChatRowHeight,
                        height: DesignTokens.Size.aiChatRowHeight
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("新对话 (⌘N)")
            .accessibilityLabel("新对话")
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    // MARK: - 列表

    private var list: some View {
        let sections = controller.sections
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        Text(section.title)
                            .font(DesignTokens.Typography.keyCap)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.horizontal, DesignTokens.Spacing.xl)
                            .padding(.top, DesignTokens.Spacing.lg)
                            .padding(.bottom, DesignTokens.Spacing.xs)

                        ForEach(section.sessions) { session in
                            row(for: session)
                                .id(session.id)
                        }
                    }

                    if sections.isEmpty {
                        Text(controller.sidebarFilter.isEmpty ? "还没有对话" : "没有匹配的对话")
                            .font(DesignTokens.Typography.rowTrailing)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, DesignTokens.Spacing.xxl)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.md)
            }
            .scrollIndicators(.hidden)
            .onChange(of: controller.currentID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private func row(for session: ChatSession) -> some View {
        ChatSessionRow(
            id: session.id,
            title: session.title,
            isPinned: session.isPinned,
            isSelected: session.id == controller.currentID,
            isGenerating: controller.generatingIDs.contains(session.id),
            isRenaming: session.id == controller.renamingID,
            onSelect: { controller.select(session.id) },
            onTogglePin: { controller.togglePin(session.id) },
            onDelete: { controller.delete(session.id) },
            onBeginRename: { controller.beginRename(session.id) },
            onCommitRename: { controller.commitRename(session.id, title: $0) }
        )
        .equatable()
    }
}

/// 侧栏里的一行
///
/// `Equatable`：切换会话时只有「旧选中」与「新选中」两行输入变了，其余行直接跳过。
struct ChatSessionRow: View, Equatable {

    let id: UUID
    let title: String
    let isPinned: Bool
    let isSelected: Bool
    let isGenerating: Bool
    let isRenaming: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: (String) -> Void

    @State private var isHovering = false
    @State private var draftTitle = ""
    @FocusState private var renameFocused: Bool

    nonisolated static func == (lhs: ChatSessionRow, rhs: ChatSessionRow) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.isPinned == rhs.isPinned
            && lhs.isSelected == rhs.isSelected && lhs.isGenerating == rhs.isGenerating
            && lhs.isRenaming == rhs.isRenaming
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            if isRenaming {
                TextField("标题", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.rowTrailing)
                    .focused($renameFocused)
                    .onSubmit { onCommitRename(draftTitle) }
                    .onAppear {
                        draftTitle = title
                        renameFocused = true
                    }
            } else {
                Text(title)
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                trailing
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(height: DesignTokens.Size.aiChatRowHeight)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onTapGesture { if !isRenaming { onSelect() } }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("重命名", action: onBeginRename)
            Button(isPinned ? "取消置顶" : "置顶", action: onTogglePin)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return DesignTokens.Colors.selection }
        return isHovering ? DesignTokens.Colors.rowHover : .clear
    }

    @ViewBuilder
    private var trailing: some View {
        if isHovering {
            iconButton(isPinned ? "pin.slash" : "pin", help: isPinned ? "取消置顶" : "置顶", action: onTogglePin)
            iconButton("trash", help: "删除 (⌘⌫)", action: onDelete)
        } else if isGenerating {
            ProgressView()
                .controlSize(.mini)
        } else if isPinned {
            Image(systemName: "pin.fill")
                .font(DesignTokens.Typography.compactIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(DesignTokens.Typography.compactIcon)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: DesignTokens.Size.aiChatIconButton, height: DesignTokens.Size.aiChatIconButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
        .accessibilityLabel(help)
    }
}
