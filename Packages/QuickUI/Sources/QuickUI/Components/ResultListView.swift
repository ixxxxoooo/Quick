// ResultListView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 统一搜索结果列表组件
///
/// 面板中部的搜索结果列表，支持键盘导航和鼠标交互。
/// 所有模块的搜索结果都通过此组件展示。
///
/// 列表会从 header 与底栏下面**穿过**（由外壳用 `safeAreaInset` 留出栏位），
/// 靠 `edgeDissolve()` 淡出，而不是被硬切。
public struct ResultListView: View {

    /// 搜索结果项
    public let items: [SearchableItem]

    /// 当前选中索引
    @Binding public var selectedIndex: Int

    /// 悬停的结果 ID
    @State private var hoveredID: String?

    /// 初始化结果列表
    /// - Parameters:
    ///   - items: 搜索结果数组
    ///   - selectedIndex: 选中索引绑定
    public init(items: [SearchableItem], selectedIndex: Binding<Int>) {
        self.items = items
        self._selectedIndex = selectedIndex
    }

    /// 结果集的指纹
    ///
    /// 用它触发「回到顶部」，而不是用 `selectedIndex`：新一批结果的第一条可能仍然
    /// 是原来选中的那一项（下标还是 0），`onChange(of: selectedIndex)` 就不会触发，
    /// 列表会停在上一批的滚动位置 —— 而滚动条是隐藏的，用户看不出自己还停在半山腰。
    private var resultSetFingerprint: String {
        "\(items.count)|\(items.first?.id ?? "")"
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xxs) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ResultRowView(
                            item: item,
                            isSelected: index == selectedIndex,
                            isHovered: hoveredID == item.id
                        )
                        .id(item.id)
                        .onHover { hovering in
                            hoveredID = hovering ? item.id : nil
                            if hovering { selectedIndex = index }
                        }
                        .onTapGesture {
                            selectedIndex = index
                            item.action()
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
            // 系统滚动条和面板的玻璃语言冲突：它是为带标题栏的窗口设计的。
            // 面板高度固定、条目数有限，滚动位置靠键盘导航已经足够可感知。
            .scrollIndicators(.never)
            .onChange(of: resultSetFingerprint) { _, _ in
                guard let first = items.first?.id else { return }
                // 不加动画：换一批结果时从中间滑回顶部会让人以为列表在乱动
                proxy.scrollTo(first, anchor: .top)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                guard newIndex >= 0, newIndex < items.count else { return }
                withAnimation(.easeOut(duration: DesignTokens.Duration.scrollReveal)) {
                    proxy.scrollTo(items[newIndex].id, anchor: .center)
                }
            }
        }
        .edgeDissolve()
    }
}

// MARK: - 搜索结果行视图

/// 单行搜索结果
///
/// 单行布局：图标 · 标题 ·（弹性）· 右侧类型标签。参考实现也是这个形状 ——
/// 副标题放在标题下方会把行高翻倍，一屏能看到的条目就少了一半。
struct ResultRowView: View {
    let item: SearchableItem
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            resultIcon
                .frame(width: DesignTokens.Size.rowIcon, height: DesignTokens.Size.rowIcon)

            Text(item.title)
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: DesignTokens.Spacing.md)

            if let hint = item.shortcutHint {
                KeyCapChip(text: hint, style: .outline, scale: .compact)
            }

            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                .fill(
                    isSelected
                        ? DesignTokens.Colors.selection
                        : isHovered ? DesignTokens.Colors.rowHover : .clear
                )
        }
        .contentShape(Rectangle())
    }

    /// 图标视图（根据类型决定展示方式）
    @ViewBuilder
    private var resultIcon: some View {
        switch item.iconType {
        case .symbol:
            Image(systemName: item.icon)
                .font(DesignTokens.Typography.iconGlyph)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        case .appIcon(let path):
            // 使用稳定的路径标识，避免每次 body 重建 NSImage 触发 AttributeGraph 死循环
            AppIconImage(path: path)
        case .image(let name):
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

/// 应用图标（按路径缓存，避免 SwiftUI 无限刷新）
private struct AppIconImage: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .font(DesignTokens.Typography.iconGlyph)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .onAppear {
            guard image == nil else { return }
            image = NSWorkspace.shared.icon(forFile: path)
        }
    }
}
