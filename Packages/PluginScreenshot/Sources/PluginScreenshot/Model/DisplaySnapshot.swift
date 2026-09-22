// DisplaySnapshot.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics
import Foundation

/// 一次「冻结屏幕」：某块显示器在触发那一刻的完整画面
///
/// 纯数据，坐标换算也在这里 —— 它是画布局部坐标与图像像素坐标之间唯一的桥。
struct DisplaySnapshot: Sendable {

    /// 显示器 id
    let displayID: CGDirectDisplayID

    /// AppKit 全局坐标（原点左下、单位 point）
    let screenFrameInPoints: CGRect

    /// `NSScreen.backingScaleFactor`，仅作参考
    let nominalScaleFactor: CGFloat

    /// 冻结画面
    let image: CGImage

    var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    /// 真实比例。缩放显示器下会与 `nominalScaleFactor` 不一致，换算一律走它
    var effectiveScale: CGFloat {
        screenFrameInPoints.width > 0
            ? CGFloat(image.width) / screenFrameInPoints.width
            : nominalScaleFactor
    }

    /// 画布局部矩形（原点左下）→ 图像像素矩形（原点左上）
    func pixelRect(fromLocalRect rect: CGRect) -> CGRect {
        let scale = effectiveScale
        return CGRect(
            x: rect.minX * scale,
            y: (screenFrameInPoints.height - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
    }
}
