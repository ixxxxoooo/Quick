// ClipboardListView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickPlatform
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

    /// 悬停高亮的条目 ID
    ///
    /// **放在列表这一层，不放在行里。** 行各自持有 `@State isHovered` 时，键盘一动
    /// 列表就滚，而滚动不会给指针底下那一行补一次 `onHover(false)` —— 旧的灰色高亮
    /// 留在原地，和键盘选中项同时亮着，看起来就是一层残影。列表统一持有，
    /// 键盘一移动就能一次全清掉。
    @State private var hoveredID: UUID?

    /// 搜索文本
    ///
    /// 来自面板头部的插件内搜索框（`PluginSearchQuery`）。分离窗口里没有这个环境，
    /// `search` 为 `nil`，退化成「不过滤」。
    @Environment(PluginSearchQuery.self) private var search: PluginSearchQuery?

    /// 本视图是否持有键盘焦点
    ///
    /// **方向键与回车要先有人接。** 插件模式下搜索框不在视图树里，没有这句焦点声明的话
    /// 焦点会落在面板本身，`onKeyPress` 一个都收不到 —— 它们是「视图或其后代获得焦点时」
    /// 才触发的。这是 `docs/ui.md` §2b 记过的同一个坑：键盘不能指望「挂上去就有人送」。
    ///
    /// 有头部搜索框时反过来：焦点在搜索框，方向键与回车由面板转给 `search.move/submit/tab`，
    /// 这里不再抢焦点。
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

    /// 头部是否有真正的搜索框（分离窗口的兜底对象不算）
    private var hasHeaderSearch: Bool { search?.hasHeaderField == true }

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
        let searchText = search?.text ?? ""
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
        //
        // **头部搜索框默认不抢焦点**（`SearchFieldView(autoFocus: false)`），所以这里
        // 始终自己取焦点：方向键由面板转接，打字要靠 ⌘F 把焦点交给搜索框。
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            // 声明「方向键与回车归我」，面板据此在 AppKit 层把它们转成命令
            if hasHeaderSearch {
                search?.wantsNavigation = true
            }
            isFocused = true
        }
        // 面板把上下 / 左右 / 回车变成请求记在 `commandToken` 上，这里取走并执行
        .onChange(of: search?.commandToken) { _, _ in
            guard let command = search?.lastCommand else { return }
            switch command {
            case .move(let delta):
                moveSelection(direction: delta)
            case .tab(let delta):
                switchTab(direction: delta)
            case .submit:
                confirmSelection()
            }
        }
        // 过滤词一变，结果集就换了一批，选中项回到第一条
        .onChange(of: search?.text ?? "") { _, _ in
            selectedIndex = 0
            hoveredID = nil
        }
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
                            isHovered: hoveredID == entry.id,
                            onSelect: {
                                selectAndCopy(entry)
                            },
                            onToggleFavorite: {
                                store.toggleFavorite(entry.id)
                            },
                            onDelete: {
                                store.remove(entry.id)
                            },
                            onHoverChange: { hovering in
                                if hovering {
                                    hoveredID = entry.id
                                } else if hoveredID == entry.id {
                                    hoveredID = nil
                                }
                            },
                            onCopy: {
                                copyOnly(entry)
                            }
                        )
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
            // 系统滚动条是为带标题栏的窗口设计的，和面板的玻璃语言冲突（见 docs/ui.md）。
            // 面板高度固定、条目数有限，滚动位置靠键盘导航足够可感。
            .scrollIndicators(.never)
            // 选中跟随与主搜索列表同一套：碰到边缘才滚，且**不做动画**（见 docs/ui.md）。
            // 这里的行高还不一样（图片行单行、文本行两行），动画追着变高的行更糊。
            .onChange(of: selectedIndex) { _, newIndex in
                let entries = currentEntries
                guard newIndex >= 0, newIndex < entries.count else { return }
                proxy.scrollTo(
                    entries[newIndex].id,
                    anchor: ListScrollFollow.anchor(for: newIndex, count: entries.count)
                )
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
            hoveredID = nil
        }
    }

    private func moveSelection(direction: Int) {
        // 键盘一动就把悬停高亮清掉：指针没动，底下那一行已经换人了，
        // 留着就是和选中项抢眼的一层残影。
        hoveredID = nil
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

    /// 主操作：复制并粘贴回面板打开前的那个应用
    ///
    /// 内容先写好剪贴板，再发粘贴事件由宿主负责「隐藏面板 → 交还焦点 → 合成 ⌘V」。
    /// 目标应用不是可输入的地方时，⌘V 自然什么都不发生，不需要我们判定。
    private func selectAndCopy(_ entry: ClipboardEntry) {
        writeToPasteboard(entry)
        EventBus.shared.post(PasteIntoPreviousAppEvent())
    }

    /// 仅复制到剪贴板（右键菜单），不粘贴、不隐藏面板之外的额外动作
    private func copyOnly(_ entry: ClipboardEntry) {
        writeToPasteboard(entry)
        EventBus.shared.post(HidePaletteEvent())
    }

    private func writeToPasteboard(_ entry: ClipboardEntry) {
        if entry.type == .image, let data = entry.imageData {
            // 图片直接写 PNG（走 PasteboardService 的 copyImage 会丢失原始字节）
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
        } else {
            // showHUD 关掉：粘贴本身就是反馈，不必再叠一层「已复制」
            EventBus.shared.post(CopyToClipboardEvent(text: entry.text, showHUD: false))
        }
    }
}

// MARK: - 行视图

/// 剪贴板条目行视图
///
/// **无状态：悬停与否由列表传入，不在行里记。** 行自己记 `@State isHovered` 的话，
/// 键盘移动导致列表滚动时没人来清它，旧的灰色高亮会留在原地（见 `ClipboardListView.hoveredID`）。
struct ClipboardRowView: View {
    let entry: ClipboardEntry
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    /// 指针进出这一行（由列表统一记录）
    let onHoverChange: (Bool) -> Void

    /// 仅复制（不动面板、不粘贴）
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 左侧图标或缩略图
            leadingContent
            // 主要内容
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                // 图片不再用文字说明，左侧缩略图就是预览
                if entry.type != .image {
                    Text(entry.preview)
                        .font(DesignTokens.Typography.rowTitle)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(2)
                }

                metadataRow
            }

            Spacer(minLength: 0)

            favoriteButton
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
        .onHover(perform: onHoverChange)
        .onTapGesture { onSelect() }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label("粘贴到当前应用", systemImage: "arrow.down.doc")
            }

            Button {
                onCopy()
            } label: {
                Label("仅复制", systemImage: "doc.on.doc")
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

    // MARK: - 元信息

    /// 来源应用 / 时间
    ///
    /// 不再显示内容类型名（「文本」「图片」…）：行本身已经说明了它是什么，
    /// 类型标签只是噪音。
    private var metadataRow: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if let source = entry.sourceAppName {
                sourceBadge(source)
            }

            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    /// 来源应用：能拿到图标就显示图标，否则退回一个通用符号
    private func sourceBadge(_ name: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            if let bundleID = entry.sourceBundleID,
                let icon = IconCache.shared.icon(forBundleID: bundleID)
            {
                Image(nsImage: icon)
                    .resizable()
                    .frame(
                        width: DesignTokens.Size.clipboardSourceIcon,
                        height: DesignTokens.Size.clipboardSourceIcon
                    )
            } else {
                Image(systemName: "app")
                    .font(DesignTokens.Typography.compactIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Text(name)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .lineLimit(1)
        }
    }

    // MARK: - 收藏

    /// 右侧的收藏按钮：点一下切换收藏，不影响整行的「复制」手势
    private var favoriteButton: some View {
        Button {
            onToggleFavorite()
        } label: {
            Image(systemName: entry.isFavorite ? "star.fill" : "star")
                .font(DesignTokens.Typography.inlineIcon)
                .foregroundStyle(
                    entry.isFavorite ? DesignTokens.Colors.warning : DesignTokens.Colors.textTertiary
                )
                .frame(
                    width: DesignTokens.Size.clipboardFavoriteButton,
                    height: DesignTokens.Size.clipboardFavoriteButton
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.isFavorite ? "取消收藏" : "收藏")
        .help(entry.isFavorite ? "取消收藏" : "收藏")
    }

    @ViewBuilder
    private var leadingContent: some View {
        if entry.type == .image, let data = entry.imageData,
            let nsImage = NSImage(data: data)
        {
            // 图片直接当预览看：高度固定，宽度按比例，宽图也不会撑破行
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    maxWidth: DesignTokens.Size.clipboardThumbMaxWidth,
                    maxHeight: DesignTokens.Size.clipboardThumbHeight,
                    alignment: .leading
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row))
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
