// ToolbarPlacement.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics

/// 标注工具栏相对选区的摆放规则（纯函数，可独立测试）
///
/// 从 `OverlayCanvasView` 里抽出来：摆放只依赖三个几何量，不需要视图就能验证。
/// 坐标沿用画布约定：局部坐标，原点在左下。
enum ToolbarPlacement {

    /// 计算工具栏的 frame
    ///
    /// 优先级：选区**下方** → 选区**上方** → 都放不下（选区几乎占满整屏）时贴在选区**内部**底部。
    /// 水平方向与选区左缘对齐，并整体夹在画布内。
    ///
    /// - Parameters:
    ///   - selection: 选区（画布局部坐标）
    ///   - size: 工具栏自身尺寸
    ///   - bounds: 画布范围
    ///   - margin: 与选区、画布边缘的最小间隙
    static func frame(
        near selection: CGRect, size: CGSize, in bounds: CGRect, margin: CGFloat
    ) -> CGRect {
        let minX = bounds.minX + margin
        let maxX = bounds.maxX - size.width - margin
        // 工具栏比画布还宽时 maxX < minX：此时贴左，宁可右侧被裁也不要左侧看不见
        let x = maxX < minX ? minX : min(max(minX, selection.minX), maxX)

        let minY = bounds.minY + margin
        let maxY = bounds.maxY - size.height - margin

        let below = selection.minY - size.height - margin
        if below >= minY {
            return CGRect(origin: CGPoint(x: x, y: below), size: size)
        }
        let above = selection.maxY + margin
        if above <= maxY {
            return CGRect(origin: CGPoint(x: x, y: above), size: size)
        }
        // 上下都放不下：落在选区内部底边，仍夹在画布内
        let inside = min(max(minY, selection.minY + margin), max(minY, maxY))
        return CGRect(origin: CGPoint(x: x, y: inside), size: size)
    }
}
