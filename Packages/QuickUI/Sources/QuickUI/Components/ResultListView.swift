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
            .onChange(of: selectedIndex) { _, newIndex in
                guard newIndex >= 0, newIndex < items.count else { return }
                withAnimation(.easeOut(duration: DesignTokens.Duration.scrollReveal)) {
                    proxy.scrollTo(items[newIndex].id, anchor: .center)
                }
            }
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < items.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.return) {
            guard selectedIndex >= 0, selectedIndex < items.count else { return .ignored }
            items[selectedIndex].action()
            return .handled
        }
    }
}

// MARK: - 搜索结果行视图

/// 单行搜索结果
struct ResultRowView: View {
    let item: SearchableItem
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            // 图标
            resultIcon
                .frame(width: DesignTokens.Size.rowIcon, height: DesignTokens.Size.rowIcon)

            // 标题和副标题
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(item.title)
                    .font(DesignTokens.Typography.rowTitle)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 快捷键提示
            if let hint = item.shortcutHint {
                Text(hint)
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(DesignTokens.Colors.controlSurface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                .fill(
                    isSelected
                        ? DesignTokens.Colors.selection : isHovered ? DesignTokens.Colors.rowHover : .clear)
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
