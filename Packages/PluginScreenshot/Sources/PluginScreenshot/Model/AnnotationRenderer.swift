// AnnotationRenderer.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics
import CoreText
import Foundation

/// 把标注画进一个 **CoreGraphics 位图上下文（原点左下）**
///
/// 标注的几何量在传进来之前必须已经换算成该上下文的像素坐标（见 `Annotation.transformed`）。
/// 实时预览与最终烘焙共用这一份绘制逻辑，两处不会画出不同的样子。
enum AnnotationRenderer {

    /// 绘制全部标注
    /// - Parameters:
    ///   - annotations: 目标坐标系的标注
    ///   - context: 位图上下文（原点左下）
    ///   - baseImage: 底图，马赛克要从它取样；为 nil 时马赛克退化成灰块
    static func draw(_ annotations: [Annotation], in context: CGContext, baseImage: CGImage?) {
        for annotation in annotations {
            draw(annotation, in: context, baseImage: baseImage)
        }
    }

    static func draw(_ annotation: Annotation, in context: CGContext, baseImage: CGImage?) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(max(1, annotation.lineWidth))
        context.setLineJoin(.round)
        context.setLineCap(.round)

        switch annotation.kind {
        case .rectangle(let rect):
            context.addPath(roundedPath(rect, radius: min(rect.width, rect.height) * 0.08))
            context.strokePath()

        case .ellipse(let rect):
            context.strokeEllipse(in: rect)

        case .arrow(let from, let to):
            drawArrow(from: from, to: to, lineWidth: annotation.lineWidth, in: context)

        case .pen(let points):
            strokePolyline(points, in: context)

        case .highlight(let points):
            context.setStrokeColor(
                CGColor(
                    srgbRed: annotation.color.red, green: annotation.color.green,
                    blue: annotation.color.blue, alpha: 0.35))
            context.setLineWidth(max(6, annotation.lineWidth * 6))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            strokePolyline(points, in: context)

        case .text(let origin, let string, let fontSize):
            drawText(string, at: origin, fontSize: fontSize, color: annotation.color, in: context)

        case .mosaic(let rect):
            drawMosaic(rect, baseImage: baseImage, in: context)

        case .counter(let center, let value):
            drawCounter(value, at: center, color: annotation.color, in: context)
        }
    }

    // MARK: - 形状

    private static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(
            roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func strokePolyline(_ points: [CGPoint], in context: CGContext) {
        guard points.count > 1 else { return }
        context.beginPath()
        context.move(to: points[0])
        for point in points.dropFirst() { context.addLine(to: point) }
        context.strokePath()
    }

    private static func drawArrow(
        from: CGPoint, to: CGPoint, lineWidth: CGFloat, in context: CGContext
    ) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.5 else { return }

        let ux = dx / length
        let uy = dy / length
        let headLength = min(length, max(10, lineWidth * 3.5))
        let headWidth = headLength * 0.66

        let base = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        let perpX = -uy
        let perpY = ux

        context.beginPath()
        context.move(to: from)
        context.addLine(to: base)
        context.strokePath()

        context.beginPath()
        context.move(to: to)
        context.addLine(
            to: CGPoint(x: base.x + perpX * headWidth / 2, y: base.y + perpY * headWidth / 2))
        context.addLine(
            to: CGPoint(x: base.x - perpX * headWidth / 2, y: base.y - perpY * headWidth / 2))
        context.closePath()
        context.fillPath()
    }

    // MARK: - 文字与序号

    private static func font(size: CGFloat) -> CTFont {
        CTFontCreateWithName("Helvetica" as CFString, max(1, size), nil)
    }

    private static func drawText(
        _ string: String, at origin: CGPoint, fontSize: CGFloat, color: RGBAColor, in context: CGContext
    ) {
        guard !string.isEmpty else { return }
        let attributed = NSAttributedString(
            string: string,
            attributes: [
                .font: font(size: fontSize),
                .foregroundColor: color.cgColor
            ])
        let line = CTLineCreateWithAttributedString(attributed)

        // 加一圈描边，浅色背景上的白字也读得清
        context.saveGState()
        context.setTextDrawingMode(.fillStroke)
        context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
        context.setLineWidth(max(1, fontSize * 0.12))
        context.textPosition = origin
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawCounter(
        _ value: Int, at center: CGPoint, color: RGBAColor, in context: CGContext
    ) {
        let radius: CGFloat = 13
        context.setFillColor(color.cgColor)
        context.fillEllipse(
            in: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2))

        let string = "\(value)"
        let attributed = NSAttributedString(
            string: string,
            attributes: [
                .font: font(size: radius * 1.25),
                .foregroundColor: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        context.textPosition = CGPoint(
            x: center.x - bounds.width / 2,
            y: center.y - bounds.height / 2 - bounds.origin.y)
        CTLineDraw(line, context)
    }

    // MARK: - 马赛克

    /// 把底图对应区域缩到 1/块大小再放大回去，得到像素化效果
    private static func drawMosaic(_ rect: CGRect, baseImage: CGImage?, in context: CGContext) {
        let target = rect.integral
        guard target.width >= 2, target.height >= 2 else { return }

        guard let baseImage else {
            context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            context.fill(target)
            return
        }

        let imageHeight = CGFloat(baseImage.height)
        let cropRect = CGRect(
            x: target.minX, y: imageHeight - target.maxY,
            width: target.width, height: target.height
        ).integral
        guard let sub = baseImage.cropping(to: cropRect) else { return }

        let block: CGFloat = 10
        let smallWidth = max(1, Int((target.width / block).rounded()))
        let smallHeight = max(1, Int((target.height / block).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let small = CGContext(
                data: nil, width: smallWidth, height: smallHeight,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        small.interpolationQuality = .high
        small.draw(sub, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        guard let smallImage = small.makeImage() else { return }

        context.saveGState()
        context.interpolationQuality = .none
        context.draw(smallImage, in: target)
        context.restoreGState()
    }
}
