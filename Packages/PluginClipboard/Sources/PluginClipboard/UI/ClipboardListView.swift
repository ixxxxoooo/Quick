// ClipboardListView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickUI
import SwiftUI

/// 剪贴板历史列表视图
///
/// 支持标签切换（全部/文本/图片/收藏）、键盘导航（上下选择、左右切换标签）。
struct ClipboardListView: View {

    let store: ClipboardStore

    /// 当前选中的标签
    @State private var selectedTab: ClipboardTab = .all

    /// 当前选中条目索引
    @State private var selectedIndex: Int = 0

    /// 搜索文本
    @State private var searchText = ""

    /// 本视图是否持有键盘焦点
    ///
    /// **方向键与回车要先有人接。** 插件模式下搜索框不在视图树里，没有这句焦点声明的话
    /// 焦点会落在面板本身，`onKeyPress` 一个都收不到 —— 它们是「视图或其后代获得焦点时」
    /// 才触发的。这是 `docs/ui.md` §2b 记过的同一个坑：键盘不能指望「挂上去就有人送」。
    @FocusState private var isFocused: Bool

    /// 标签枚举
    enum ClipboardTab: String, CaseIterable {
        case all = "全部"
        case text = "文本"
        case image = "图片"
        case favorites = "收藏"

        var icon: String {
            switch self {
            case .all: "tray.full"
            case .text: "doc.text"
            case .image: "photo"
            case .favorites: "star"
            }
        }
    }

    /// 当前标签下的条目
    private var currentEntries: [ClipboardEntry] {
        let base: [ClipboardEntry]
        switch selectedTab {
        case .all:
            base = store.entries
        case .text:
            base = store.entries.filter { $0.type != .image }
        case .image:
            base = store.imageEntries
        case .favorites:
            base = store.favorites
        }
        if searchText.isEmpty { return base }
        let lower = searchText.lowercased()
        return base.filter {
            $0.text.lowercased().contains(lower)
                || $0.preview.lowercased().contains(lower)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标签栏
            tabBar

            Divider()
                .padding(.horizontal, DesignTokens.Spacing.lg)

            // 条目列表
            if currentEntries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        // 焦点必须落在内容上，键盘才走得通：`.focusable()` 让这个视图可以成为第一响应者，
        // `.focused` 把它绑到 `isFocused`，`onAppear` 里主动取一次 —— 插件视图是随导航
        // 新插进视图树的，没人会替它取焦点。`.focusEffectDisabled()` 是因为焦点圈在这里
        // 只会糊住整块内容：面板自己就是「焦点所在」的视觉提示，不需要再描一圈。
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        // **`phases:` 要显式写。** 单键重载 `onKeyPress(.downArrow) { }` 不带 phases，
        // 只响应第一次按下：长按方向键不会连续移动，手感就是「按住了没反应」。
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { _ in
            switchTab(direction: -1)
            return .handled
        }
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { _ in
            switchTab(direction: 1)
            return .handled
        }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in
            moveSelection(direction: -1)
            return .handled
        }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in
            moveSelection(direction: 1)
            return .handled
        }
        .onKeyPress(.return) {
            confirmSelection()
            return .handled
        }
        // 列表会在面板开着的时候变短（右键删掉一条、历史被裁剪）。下标停在界外时，上下键
        // 要连按几次才「回到列表里」，看起来就是按了不动 —— 变短就立刻夹回范围内。
        .onChange(of: currentEntries.count) { _, count in
            selectedIndex = ClipboardListNavigation.clamp(selectedIndex, count: count)
        }
    }

    // MARK: - 标签栏

    private var tabBar: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(ClipboardTab.allCases, id: \.rawValue) { tab in
                tabButton(tab)
            }

            Spacer()

            // 条目计数
            Text("\(currentEntries.count) 条")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            // 清空按钮
            Button {
                store.clearHistory()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("清空历史（保留收藏）")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private func tabButton(_ tab: ClipboardTab) -> some View {
        let isSelected = selectedTab == tab
        let count: Int = {
            switch tab {
            case .all: store.entries.count
            case .text: store.entries.filter { $0.type != .image }.count
            case .image: store.imageEntries.count
            case .favorites: store.favorites.count
            }
        }()

        return Button {
            selectedTab = tab
            selectedIndex = 0
        } label: {
            HStack(spacing: DesignTokens.Spacing.xxs) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11))
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : DesignTokens.Colors.textTertiary)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(isSelected ? .white : DesignTokens.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 列表

    private var entryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xxs) {
                    ForEach(Array(currentEntries.enumerated()), id: \.element.id) { index, entry in
                        ClipboardRowView(
                            entry: entry,
                            isSelected: index == selectedIndex,
                            onSelect: {
                                selectAndCopy(entry)
                            },
                            onToggleFavorite: {
                                store.toggleFavorite(entry.id)
                            },
                            onDelete: {
                                store.remove(entry.id)
                            }
                        )
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                let entries = currentEntries
                if newIndex >= 0, newIndex < entries.count {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(entries[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: selectedTab == .favorites ? "star.slash" : "clipboard")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(emptyMessage)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        switch selectedTab {
        case .all: "暂无剪贴板历史\n复制内容后会自动记录"
        case .text: "暂无文本记录"
        case .image: "暂无图片记录\n复制图片后会自动记录"
        case .favorites: "暂无收藏\n右键条目可添加收藏"
        }
    }

    // MARK: - 键盘导航

    private func switchTab(direction: Int) {
        let tabs = ClipboardTab.allCases
        guard let currentIndex = tabs.firstIndex(of: selectedTab) else { return }
        let newIndex = currentIndex + direction
        if newIndex >= 0, newIndex < tabs.count {
            selectedTab = tabs[newIndex]
            selectedIndex = 0
        }
    }

    private func moveSelection(direction: Int) {
        selectedIndex = ClipboardListNavigation.step(
            from: selectedIndex,
            direction: direction,
            count: currentEntries.count
        )
    }

    private func confirmSelection() {
        let entries = currentEntries
        guard selectedIndex >= 0, selectedIndex < entries.count else { return }
        selectAndCopy(entries[selectedIndex])
    }

    private func selectAndCopy(_ entry: ClipboardEntry) {
        if entry.type == .image, let data = entry.imageData {
            // 图片复制到剪贴板
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
            EventBus.shared.post(ShowHUDEvent(message: "已复制图片", tone: .success))
        } else {
            EventBus.shared.post(CopyToClipboardEvent(text: entry.text))
        }
        EventBus.shared.post(HidePaletteEvent())
    }
}

// MARK: - 行视图

/// 剪贴板条目行视图
struct ClipboardRowView: View {
    let entry: ClipboardEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 左侧图标或缩略图
            leadingContent

            // 主要内容
            VStack(alignment: .leading, spacing: 2) {
                if entry.type == .image {
                    Text(entry.preview)
                        .font(DesignTokens.Typography.rowTitle)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                } else {
                    Text(entry.preview)
                        .font(DesignTokens.Typography.rowTitle)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(2)
                }

                HStack(spacing: DesignTokens.Spacing.xs) {
                    // 类型标签
                    Text(entry.type.displayName)
                        .font(.system(size: 10))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                        )
                        .foregroundStyle(DesignTokens.Colors.textTertiary)

                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }

            Spacer()

            // 收藏标记
            if entry.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 12))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.2)
                        : (isHovered ? DesignTokens.Colors.rowHover : .clear)
                )
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
            }
        }
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                onToggleFavorite()
            } label: {
                Label(
                    entry.isFavorite ? "取消收藏" : "收藏",
                    systemImage: entry.isFavorite ? "star.slash" : "star"
                )
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        if entry.type == .image, let data = entry.imageData,
            let nsImage = NSImage(data: data)
        {
            // 图片缩略图
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            // 文字类图标
            Image(systemName: entry.type.icon)
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                )
        }
    }
}
