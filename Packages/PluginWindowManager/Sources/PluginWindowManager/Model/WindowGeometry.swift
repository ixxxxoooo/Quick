// WindowGeometry.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 窗口目标 frame 的纯计算
///
/// 布局比例（`WindowLayout.rect`）到具体矩形的换算与屏幕、辅助功能 API 无关，
/// 单独放在这里才能在没有真实显示器的情况下断言；`WindowMover` 只保留 AX 调用。
enum WindowGeometry {

    /// 按布局比例算出窗口在可见区域内的目标 frame
    ///
    /// 坐标系是 AppKit 的（原点左下、y 向上），布局比例却按「从上往下」的直觉书写
    /// （`topHalf` 的 y 是 0），所以这里必须把 y 翻过来。
    /// - Parameters:
    ///   - visibleFrame: 屏幕的可见区域（已扣掉菜单栏和 Dock）
    ///   - layout: 目标布局
    /// - Returns: AppKit 坐标系下的窗口 frame
    static func frame(in visibleFrame: CGRect, layout: WindowLayout) -> CGRect {
        let ratio = layout.rect
        return CGRect(
            x: visibleFrame.origin.x + visibleFrame.width * ratio.x,
            y: visibleFrame.origin.y + visibleFrame.height * (1.0 - ratio.y - ratio.h),
            width: visibleFrame.width * ratio.w,
            height: visibleFrame.height * ratio.h
        )
    }

    /// 送给 AX 的窗口位置
    ///
    /// AX 使用左上原点，而 `frame(in:layout:)` 给的是左下原点，需要按可见区域的
    /// 上边界（`maxY`）再做一次翻转 —— 注意翻转基准是可见区域而不是整块屏幕，
    /// 换掉会让窗口整体上移一个菜单栏的高度。
    static func accessibilityPosition(in visibleFrame: CGRect, layout: WindowLayout) -> CGPoint {
        let target = frame(in: visibleFrame, layout: layout)
        return CGPoint(x: target.origin.x, y: visibleFrame.maxY - target.maxY)
    }

    /// 送给 AX 的窗口大小
    static func accessibilitySize(in visibleFrame: CGRect, layout: WindowLayout) -> CGSize {
        frame(in: visibleFrame, layout: layout).size
    }
}
