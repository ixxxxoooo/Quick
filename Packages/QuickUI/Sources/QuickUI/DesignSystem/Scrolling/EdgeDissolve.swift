// EdgeDissolve.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 列表从浮动栏下方穿过时的边缘渐隐
///
/// 面板里的列表**不是**被 header 和底栏硬切的：内容从它们下面穿过，靠这层遮罩淡出。
/// 这是参考实现的同一套做法（它的注释原话是「the edge dissolve ghosts the rows
/// passing beneath」）。
///
/// 两个容易做错的地方：
///
/// 1. **静止贴边时必须完全不淡。** 否则第一行会莫名其妙变浅。所以渐隐强度由
///    「内容滚出去多少」驱动，滚出越多越淡，贴边时为 0。
/// 2. **遮罩必须覆盖滚动视图的完整 frame。** `safeAreaInset` 会把内容内缩，
///    若遮罩只覆盖内容区，渐变会整体内移，把栏位下面那一带裁成黑色。
///    所以这里用 `GeometryReader` + `ignoresSafeArea()` 撑满。
struct EdgeDissolveMask: ViewModifier {

    /// 顶部渐隐带 = header 高度 + 上内边距 + 一段越过 header 的余量
    private var topFade: CGFloat {
        DesignTokens.Size.headerHeight + DesignTokens.Size.headerPadding
            + DesignTokens.Size.edgeFadeHeight
    }

    /// 底部渐隐带 = 底栏高度 + 一段越过底栏的余量
    private var bottomFade: CGFloat {
        DesignTokens.Size.bottomBarHeight + DesignTokens.Size.edgeFadeHeight
    }

    /// 滚到底时边缘保留的最小不透明度
    ///
    /// 不归零：留一点影读起来像「后面还有内容」，归零会让边缘看起来像被裁掉了。
    private static let topMinAlpha: CGFloat = 0.15
    private static let bottomMinAlpha: CGFloat = 0.25

    @State private var topDistance: CGFloat = 0
    @State private var bottomDistance: CGFloat = 0
    @State private var canScroll = false

    private struct ScrollState: Equatable {
        var top: CGFloat
        var bottom: CGFloat
        var canScroll: Bool
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollState.self) { geometry in
                let visible =
                    geometry.containerSize.height - geometry.contentInsets.top
                    - geometry.contentInsets.bottom
                return ScrollState(
                    top: geometry.contentOffset.y + geometry.contentInsets.top,
                    bottom: geometry.contentSize.height + geometry.contentInsets.bottom
                        - geometry.containerSize.height - geometry.contentOffset.y,
                    canScroll: geometry.contentSize.height > visible
                )
            } action: { _, new in
                topDistance = max(0, new.top)
                bottomDistance = max(0, new.bottom)
                canScroll = new.canScroll
            }
            .mask(
                GeometryReader { geometry in
                    LinearGradient(
                        stops: stops(height: geometry.size.height),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
            )
    }

    /// 渐变断点
    ///
    /// 边缘 alpha 从 0 升到 `topAlpha` / `bottomAlpha`，中段全不透明。
    /// `topAlpha` 随滚出距离从 1 降到下限 —— 贴边时是 1（等于不淡），
    /// 滚出一整条渐隐带后降到下限。
    private func stops(height: CGFloat) -> [Gradient.Stop] {
        guard canScroll, height > 0 else {
            return [.init(color: .black, location: 0)]
        }

        let topAlpha = 1 - (1 - Self.topMinAlpha) * min(topDistance / topFade, 1)
        let bottomAlpha = 1 - (1 - Self.bottomMinAlpha) * min(bottomDistance / bottomFade, 1)

        // 带外那两个全不透明的断点是必需的：少了它们，渐变会在两个低 alpha 之间
        // 跨越整片列表线性插值，把中间的每一行都冲淡。
        return [
            .init(color: .black.opacity(0), location: 0),
            .init(color: .black.opacity(topAlpha), location: topFade / 2 / height),
            .init(color: .black, location: topFade / height),
            .init(color: .black, location: 1 - bottomFade / height),
            .init(color: .black.opacity(bottomAlpha), location: 1 - bottomFade / 2 / height),
            .init(color: .black.opacity(0), location: 1)
        ]
    }
}

extension View {
    /// 让滚动内容在浮动栏下方淡出，而不是被硬切
    func edgeDissolve() -> some View {
        modifier(EdgeDissolveMask())
    }
}
