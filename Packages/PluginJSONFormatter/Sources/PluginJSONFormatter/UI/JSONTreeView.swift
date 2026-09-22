// JSONTreeView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// JSON 可折叠树视图
///
/// 对象显示 `{n}`、数组显示 `[n]`，点圆点或整行展开/折叠；父级搜索词命中时自动展开
/// 并加粗高亮（对齐 JSON Viewer / JSON Hero 的主流做法）。
///
/// **键盘导航走面板的插件内搜索。** 头部搜索框拿着焦点时，本视图收不到方向键，
/// 所以把导航注册到 `PluginSearchQuery.move/tab/submit` 上，由 `PalettePanel.sendEvent`
/// 在 AppKit 层转过来。方向键上下移动选中行，左右折叠/展开，回车展开或复制。
struct JSONTreeView: View {

    /// 解析好的节点树
    let root: JSONNode

    /// 搜索词（来自插件内搜索框）
    let query: String

    /// 被折叠的路径集合
    @Binding var collapsed: Set<String>

    /// 当前选中行的路径
    @Binding var selection: String?

    @Environment(PluginSearchQuery.self) private var search: PluginSearchQuery?

    private var rows: [JSONTreeRow] {
        JSONTreeLayout.rows(root: root, collapsed: collapsed, query: query)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row)
                            .id(row.id)
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .scrollIndicators(.never)
            .onChange(of: selection) { _, newValue in
                guard let newValue else { return }
                proxy.scrollTo(newValue, anchor: .center)
            }
        }
        .onAppear {
            if selection == nil { selection = rows.first?.id }
        }
        // 面板把上下 / 左右 / 回车变成请求记在 `commandToken` 上，这里取走并执行
        .onChange(of: search?.commandToken) { _, _ in
            guard let command = search?.lastCommand else { return }
            switch command {
            case .move(let delta):
                moveSelection(delta)
            case .tab(let delta):
                moveHorizontally(delta)
            case .submit:
                activateSelection()
            }
        }
    }

    // MARK: - 行

    @ViewBuilder
    private func rowView(_ row: JSONTreeRow) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Color.clear
                .frame(width: CGFloat(row.depth) * DesignTokens.Size.jsonTreeIndent)

            Group {
                if row.isContainer {
                    Image(systemName: row.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(DesignTokens.Typography.compactIcon)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                } else {
                    Color.clear
                }
            }
            .frame(width: DesignTokens.Size.headerIconSlot)

            if let key = row.key {
                Text(key)
                    .font(DesignTokens.Typography.code)
                    .fontWeight(row.matchesQuery ? .bold : .regular)
                    .foregroundStyle(
                        row.matchesQuery
                            ? DesignTokens.Colors.textPrimary
                            : DesignTokens.Colors.Syntax.key
                    )

                Text(":")
                    .font(DesignTokens.Typography.code)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            if !row.value.isEmpty {
                Text(row.value)
                    .font(DesignTokens.Typography.code)
                    .fontWeight(row.matchesQuery ? .bold : .regular)
                    .foregroundStyle(
                        row.matchesQuery
                            ? DesignTokens.Colors.textPrimary
                            : valueColor(row.kind)
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: DesignTokens.Size.jsonTreeRowHeight)
        .background(selection == row.id ? DesignTokens.Colors.selection : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { tap(row) }
    }

    private func valueColor(_ kind: JSONTreeRow.Kind) -> Color {
        switch kind {
        case .string: DesignTokens.Colors.Syntax.string
        case .number: DesignTokens.Colors.Syntax.number
        case .bool, .null: DesignTokens.Colors.Syntax.literal
        case .object, .array: DesignTokens.Colors.textSecondary
        }
    }

    // MARK: - 交互

    private var selectedRow: JSONTreeRow? {
        rows.first { $0.id == selection }
    }

    private func tap(_ row: JSONTreeRow) {
        selection = row.id
        if row.isContainer {
            toggle(row)
        } else {
            copy(row)
        }
    }

    private func toggle(_ row: JSONTreeRow) {
        guard row.isContainer else { return }
        if collapsed.contains(row.id) {
            collapsed.remove(row.id)
        } else {
            collapsed.insert(row.id)
        }
    }

    private func copy(_ row: JSONTreeRow) {
        EventBus.shared.post(CopyToClipboardEvent(text: row.copyText))
    }

    // MARK: - 键盘导航（由面板转成请求）

    private func moveSelection(_ delta: Int) {
        let list = rows
        guard !list.isEmpty else { return }
        guard let current = selection, let index = list.firstIndex(where: { $0.id == current }) else {
            selection = list.first?.id
            return
        }
        let next = min(max(index + delta, 0), list.count - 1)
        selection = list[next].id
    }

    /// 左键折叠当前节点，右键展开当前节点
    private func moveHorizontally(_ delta: Int) {
        guard let row = selectedRow, row.isContainer else { return }
        if delta < 0 {
            collapsed.insert(row.id)
        } else {
            collapsed.remove(row.id)
        }
    }

    /// 回车：容器展开/折叠，叶子复制
    private func activateSelection() {
        guard let row = selectedRow else { return }
        if row.isContainer {
            toggle(row)
        } else {
            copy(row)
        }
    }
}
