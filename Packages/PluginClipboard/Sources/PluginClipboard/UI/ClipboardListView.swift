// ClipboardListView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import ImageIO
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

    /// 悬停高亮状态
    ///
    /// **统一持有，不放在行里。** 行各自持有 `@State isHovered` 时，键盘一动列表就滚，
    /// 而滚动不会给指针底下那一行补一次 `onHover(false)` —— 旧的灰色高亮留在原地，
    /// 和键盘选中项同时亮着，看起来就是一层残影。所以由列表统一清。
    ///
    /// **用一个引用类型兜着，而不是列表上的 `@State`。** 悬停变化只该让**行**重绘：
    /// 挂成列表的状态时，指针每掠过一行都会让整个 body 重算一遍（里面有按标签计数、
    /// 按搜索词过滤这些 O(n) 的活），条目一多就成了滚动时的卡顿来源。行自己读这个对象，
    /// 变化时被失效的只有行。
    @State private var hover = ClipboardHoverState()

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
            claimNavigationAndFocus()
        }
        // 面板只是 orderOut 再 show 时 onAppear 不会再跑；shownToken 让我们重新抢回导航
        .onChange(of: search?.shownToken ?? 0) { _, _ in
            claimNavigationAndFocus()
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
            hover.clear()
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
        let counts = tabCounts
        return HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(ClipboardTab.allCases, id: \.rawValue) { tab in
                tabButton(tab, count: counts[tab] ?? 0)
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
                    .font(DesignTokens.Typography.inlineIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("清空历史（保留收藏）")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    /// 各标签的计数
    ///
    /// 一次遍历算完所有标签。以前每个按钮各自 `filter` 一遍全表 —— 四个标签就是四趟
    /// O(n)，而这个视图每次悬停变化都会重算一遍，条目一多就成了滚动时的隐形开销。
    private var tabCounts: [ClipboardTab: Int] {
        var texts = 0
        var images = 0
        var favorites = 0
        for entry in store.entries {
            if entry.type == .image { images += 1 } else { texts += 1 }
            if entry.isFavorite { favorites += 1 }
        }
        return [
            .all: store.entries.count,
            .text: texts,
            .image: images,
            .favorites: favorites
        ]
    }

    private func tabButton(_ tab: ClipboardTab, count: Int) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            selectedTab = tab
            selectedIndex = 0
        } label: {
            HStack(spacing: DesignTokens.Spacing.xxs) {
                Image(systemName: tab.icon)
                    .font(DesignTokens.Typography.compactIcon)
                Text(tab.rawValue)
                    .font(DesignTokens.Typography.keyCap).fontWeight(isSelected ? .medium : .regular)
                if count > 0 {
                    Text("\(count)")
                        .font(DesignTokens.Typography.compactKeyCap)
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
                            hover: hover,
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
                                hover.setHovered(entry.id, hovering)
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
                .font(DesignTokens.Typography.emptyStateIcon)
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

    /// 声明导航归属并把焦点落到列表上
    ///
    /// `onAppear` 与 `shownToken` 共用：后者覆盖「粘贴后面板只 orderOut、再次唤醒
    /// 时视图还在树上」的情况。
    private func claimNavigationAndFocus() {
        if hasHeaderSearch {
            search?.wantsNavigation = true
        }
        isFocused = true
    }

    private func switchTab(direction: Int) {
        let tabs = ClipboardTab.allCases
        guard let currentIndex = tabs.firstIndex(of: selectedTab) else { return }
        let newIndex = currentIndex + direction
        if newIndex >= 0, newIndex < tabs.count {
            selectedTab = tabs[newIndex]
            selectedIndex = 0
            hover.clear()
        }
    }

    private func moveSelection(direction: Int) {
        // 键盘一动就把悬停高亮清掉：指针没动，底下那一行已经换人了，
        // 留着就是和选中项抢眼的一层残影。
        hover.clear()
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
/// **不持有 `@State isHovered`，而是读列表传下来的 `hover`。** 行自己记状态的话，
/// 键盘移动导致列表滚动时没人来清它，旧的灰色高亮会留在原地（见 `ClipboardHoverState`）。
/// 读引用对象而不是收一个 `isHovered` 布尔值，是为了让悬停变化只失效这一行，
/// 不牵连列表 body 重算。
private struct ClipboardRowView: View {
    let entry: ClipboardEntry
    let isSelected: Bool
    /// 列表统一的悬停状态
    let hover: ClipboardHoverState
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    /// 指针进出这一行（由列表统一记录）
    let onHoverChange: (Bool) -> Void

    /// 仅复制（不动面板、不粘贴）
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            if entry.type == .image {
                // 图片：缩略图在上，来源/时间等元信息排在图片下面
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    leadingContent
                    metadataRow
                }
            } else {
                // 文字：不再显示左侧图标，预览与元信息占满整行
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    // 预览要压平换行、截断，对长文本是实打实的字符串扫描 —— 走缓存，
                    // 别让每次重绘、每次滚回来都重算一遍
                    Text(ClipboardPreviewCache.text(for: entry))
                        .font(DesignTokens.Typography.rowTitle)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(2)

                    metadataRow
                }
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
                        : (hover.hoveredID == entry.id ? DesignTokens.Colors.rowHover : .clear)
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
            // 图片不显示来源应用，只留时间
            if entry.type != .image, let source = entry.sourceAppName {
                sourceBadge(source)
            }

            // 用缓存好的 `FormatStyle` + `Text(_:format:)`：日期格式化在滚动里
            // 是逐行都要跑一遍的活，别每次现造一个样式
            Text(entry.timestamp, format: Self.timestampStyle)
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

    /// 时间列的格式（只建一次）
    private static let timestampStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)

    /// 图片缩略图（只有图片行才有前置内容）
    ///
    /// 高度固定，宽度按比例，宽图也不会撑破行。解码走 `ClipboardThumbnail` 的后台缩略图，
    /// 不在这里同步 `NSImage(data:)`。
    private var leadingContent: some View {
        ClipboardThumbnail(entry: entry)
    }
}

// MARK: - 图片缩略图

/// 剪贴板图片缩略图
///
/// 解码与缩放都在后台做，只把**缩小后**的位图交给 SwiftUI。原来的写法是每次行重绘都
/// `NSImage(data:)` 同步解一张全尺寸截图（可能是 Retina 下 4000+ 像素宽），滚过去一行
/// 解一张 —— 这是列表滚动卡顿的主因。缩小后的结果按条目 id 缓存，滚回来是即时的。
private struct ClipboardThumbnail: View {

    let entry: ClipboardEntry

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // 解码完成前占住同样的位置，避免行高跳一下
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .fill(DesignTokens.Colors.controlSurface)
            }
        }
        .frame(
            maxWidth: DesignTokens.Size.clipboardThumbMaxWidth,
            maxHeight: DesignTokens.Size.clipboardThumbHeight,
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row))
        .task(id: entry.id) {
            await load()
        }
    }

    private func load() async {
        if let cached = ClipboardThumbnailCache.shared.image(for: entry.id) {
            image = cached
            return
        }
        guard let data = entry.imageData else { return }

        // 后台缩放到显示尺寸再编码成小 PNG；Data 是 Sendable，可以安全跨回主线程
        let downsampled = await Task.detached(priority: .userInitiated) {
            Self.downsampledPNG(from: data)
        }.value

        guard let downsampled, let decoded = NSImage(data: downsampled) else { return }
        ClipboardThumbnailCache.shared.store(decoded, for: entry.id)
        image = decoded
    }

    /// 缩放到最长边 `thumbnailMaxPixelSize` 像素并重新编码成 PNG
    ///
    /// 全程只用 ImageIO / 位图，不碰视图，可以在主线程之外跑。
    nonisolated private static func downsampledPNG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    /// 缩略图最长边的像素数（显示尺寸 × 2，覆盖 Retina）
    nonisolated private static let thumbnailMaxPixelSize: CGFloat = 360
}

/// 缩略图缓存（按条目 id）
@MainActor
private final class ClipboardThumbnailCache {

    static let shared = ClipboardThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 200
    }

    func image(for id: UUID) -> NSImage? {
        cache.object(forKey: id.uuidString as NSString)
    }

    func store(_ image: NSImage, for id: UUID) {
        cache.setObject(image, forKey: id.uuidString as NSString)
    }
}

/// 预览文本缓存（按条目 id）
///
/// `ClipboardEntry.preview` 每次访问都要压平换行、截断，对长文本是一遍字符串扫描。
/// 条目内容不可变、id 稳定，所以按 id 缓存一次即可。
@MainActor
private enum ClipboardPreviewCache {

    private static let cache = NSCache<NSString, NSString>()

    static func text(for entry: ClipboardEntry) -> String {
        let key = entry.id.uuidString as NSString
        if let cached = cache.object(forKey: key) { return cached as String }
        let value = entry.preview
        cache.setObject(value as NSString, forKey: key)
        return value
    }
}

/// 列表统一的悬停状态
///
/// 做成引用类型让行自己去读：悬停变化只失效读它的行，不像列表 `@State` 那样
/// 带着整个 body（含 O(n) 的计数与过滤）一起重算。
@MainActor
@Observable
private final class ClipboardHoverState {

    private(set) var hoveredID: UUID?

    func setHovered(_ id: UUID, _ hovering: Bool) {
        if hovering {
            hoveredID = id
        } else if hoveredID == id {
            hoveredID = nil
        }
    }

    func clear() {
        hoveredID = nil
    }
}
