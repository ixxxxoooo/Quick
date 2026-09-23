// SuperPanelPlacement.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics

/// 面板相对光标的落点与展开方向（纯计算，可单测）
///
/// 坐标系是 AppKit 的全局坐标（原点在主屏左下、y 轴向上）。
/// 规则对齐 Fasty `calc_super_panel_position`：默认在光标右下方 6pt 处展开，
/// 右侧 / 下方空间不够就翻到左 / 上；最终严格夹进屏幕可见区。
public struct SuperPanelPlacement: Sendable, Equatable {

    public enum Horizontal: Sendable, Equatable {
        case right
        case left
    }

    public enum Vertical: Sendable, Equatable {
        case down
        case up
    }

    /// 距光标的偏移（Fasty 取 6pt：既贴得近，又不遮住指针）
    public static let offset: CGFloat = 6
    /// 距屏幕边缘的安全边距
    public static let margin: CGFloat = 8
    /// 顶部额外让出的菜单栏高度
    public static let topInset: CGFloat = 28

    public let cursor: CGPoint
    public let horizontal: Horizontal
    public let vertical: Vertical

    /// 计算落点
    ///
    /// - Parameters:
    ///   - cursor: 光标全局坐标
    ///   - panelSize: 面板尺寸
    ///   - visibleFrame: 目标屏的可见区域（已避开菜单栏与 Dock）
    /// - Returns: 落点与展开方向
    public static func resolve(
        cursor: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> SuperPanelPlacement {
        let left = visibleFrame.minX + margin
        let right = visibleFrame.maxX - margin
        let bottom = visibleFrame.minY + margin
        let top = visibleFrame.maxY - topInset

        let rightSpace = right - (cursor.x + offset)
        let leftSpace = (cursor.x - offset) - left
        let horizontal: Horizontal =
            rightSpace >= panelSize.width || rightSpace >= leftSpace ? .right : .left

        let bottomSpace = (cursor.y - offset) - bottom
        let topSpace = top - (cursor.y + offset)
        let vertical: Vertical =
            bottomSpace >= panelSize.height || bottomSpace >= topSpace ? .down : .up

        return SuperPanelPlacement(cursor: cursor, horizontal: horizontal, vertical: vertical)
    }

    /// 按给定尺寸算出夹进屏幕后的原点
    ///
    /// 内容高度变化时窗口会重排，这时要以光标为锚点重新定位：向下的面板顶边不动、
    /// 向上的面板底边不动，否则面板会在光标下方「长高」而不是「撑开」。
    public func origin(for panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        let left = visibleFrame.minX + Self.margin
        let right = visibleFrame.maxX - Self.margin
        let bottom = visibleFrame.minY + Self.margin
        let top = visibleFrame.maxY - Self.topInset

        let rawX: CGFloat =
            horizontal == .right
            ? cursor.x + Self.offset
            : cursor.x - panelSize.width - Self.offset

        let rawY: CGFloat =
            vertical == .down
            ? cursor.y - Self.offset - panelSize.height
            : cursor.y + Self.offset

        let maxX = max(left, right - panelSize.width)
        let maxY = max(bottom, top - panelSize.height)

        return CGPoint(
            x: min(max(rawX, left), maxX),
            y: min(max(rawY, bottom), maxY)
        )
    }
}
