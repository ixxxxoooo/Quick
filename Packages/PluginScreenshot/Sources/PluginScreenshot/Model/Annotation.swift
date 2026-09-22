// Annotation.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics
import Foundation

/// 标注工具
///
/// 只保留「核心版」这一档：形状、箭头、笔迹、文字、马赛克与序号。
/// 没有聚光灯 / 模糊 / 橡皮 / 裁剪 —— 那几样属于后续再加的能力。
enum AnnotationTool: String, CaseIterable, Identifiable, Sendable {
    case select
    case rectangle
    case ellipse
    case arrow
    case pen
    case highlight
    case text
    case mosaic
    case counter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "选择"
        case .rectangle: "矩形"
        case .ellipse: "椭圆"
        case .arrow: "箭头"
        case .pen: "画笔"
        case .highlight: "荧光笔"
        case .text: "文字"
        case .mosaic: "马赛克"
        case .counter: "序号"
        }
    }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .pen: "pencil"
        case .highlight: "highlighter"
        case .text: "textformat"
        case .mosaic: "squareshape.split.3x3"
        case .counter: "1.circle"
        }
    }

    /// 是否需要拖拽落笔（选择工具与序号不是）
    var isDragToDraw: Bool {
        switch self {
        case .select, .counter: false
        default: true
        }
    }
}

/// 与外观无关的 RGBA 颜色
///
/// 刻意用 CoreGraphics 而不是 `NSColor`：模型层不允许 `import AppKit`，
/// 颜色也必须能跨图层传递而不把 AppKit 拖进去。
struct RGBAColor: Equatable, Hashable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let red = RGBAColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1)
    static let blue = RGBAColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1)
    static let green = RGBAColor(red: 0.0, green: 0.831, blue: 0.420, alpha: 1)
    static let yellow = RGBAColor(red: 1.0, green: 0.800, blue: 0.0, alpha: 1)
    static let orange = RGBAColor(red: 0.843, green: 0.467, blue: 0.341, alpha: 1)
    static let white = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)

    static let palette: [RGBAColor] = [.red, .blue, .green, .yellow, .orange, .white, .black]
}

/// 一条标注
///
/// 几何量全部是**画布局部坐标（point，原点左下）**。烘焙成图片时才换算到像素。
struct Annotation: Identifiable, Equatable, Sendable {

    enum Kind: Equatable, Sendable {
        case rectangle(CGRect)
        case ellipse(CGRect)
        case arrow(from: CGPoint, to: CGPoint)
        case pen(points: [CGPoint])
        case highlight(points: [CGPoint])
        case text(origin: CGPoint, string: String, fontSize: CGFloat)
        case mosaic(CGRect)
        case counter(center: CGPoint, value: Int)
    }

    let id: UUID
    var kind: Kind
    var color: RGBAColor
    var lineWidth: CGFloat

    init(
        id: UUID = UUID(),
        kind: Kind,
        color: RGBAColor,
        lineWidth: CGFloat = 3
    ) {
        self.id = id
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
    }

    /// 平移 + 缩放到目标坐标系（烘焙到裁剪图时用）
    func transformed(offset: CGPoint, scale: CGFloat) -> Annotation {
        func point(_ value: CGPoint) -> CGPoint {
            CGPoint(x: (value.x - offset.x) * scale, y: (value.y - offset.y) * scale)
        }
        func rect(_ value: CGRect) -> CGRect {
            let origin = point(value.origin)
            return CGRect(
                x: origin.x, y: origin.y,
                width: value.width * scale, height: value.height * scale)
        }

        var copy = self
        switch kind {
        case .rectangle(let r): copy.kind = .rectangle(rect(r))
        case .ellipse(let r): copy.kind = .ellipse(rect(r))
        case .arrow(let from, let to): copy.kind = .arrow(from: point(from), to: point(to))
        case .pen(let points): copy.kind = .pen(points: points.map(point))
        case .highlight(let points): copy.kind = .highlight(points: points.map(point))
        case .text(let origin, let string, let size):
            copy.kind = .text(origin: point(origin), string: string, fontSize: size * scale)
        case .mosaic(let r): copy.kind = .mosaic(rect(r))
        case .counter(let center, let value): copy.kind = .counter(center: point(center), value: value)
        }
        copy.lineWidth = lineWidth * scale
        return copy
    }
}
