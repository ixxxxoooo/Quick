#!/usr/bin/env swift
// generate-icon.swift
// Quick — 原生 macOS 效率启动器
// @author ygw
//
// 生成 Quick 的 App 图标与菜单栏（托盘）模板图标。
//
// 设计：石墨黑 → 深灰的斜向渐变底 + 居中的白色几何「Q」字标
// （粗圆环 + 右下角圆头尾巴）。Q 与 Quick 同名，字形本身就是品牌标识。
//
// 遵循 iOS 26 / macOS 26 的图标规范：
//   - 不留圆角、不透明底、不烘焙高光与投影（系统 / Icon Composer 负责玻璃质感）
//   - 分层输出「背景 / 字标」两张源图，可直接拖进 Icon Composer 合成 Liquid Glass 图标
//
// 用法：swift Scripts/generate-icon.swift
// 产物：icon-variants/ 下的 master 与分层源图（脚本自身不写资产目录，见下方安装步骤）

import AppKit
import CoreGraphics

// MARK: - 画布与设计比例

/// 主图标画布边长（App Store / macOS 512@2x 用的都是这一档）
let canvas: CGFloat = 1024

/// 「Q」字标的比例，全部相对画布边长
///
/// 拆成比例而不是绝对像素，是为了同一套字形能缩到菜单栏的 18pt 还保持同款。
typealias QProportions = (
    outerRadius: CGFloat,
    ringThickness: CGFloat,
    tailWidth: CGFloat,
    tailStart: CGFloat,
    tailEnd: CGFloat
)

enum Mark {
    /// 圆环外半径
    static let outerRadius: CGFloat = 0.2860
    /// 圆环笔画粗细
    static let ringThickness: CGFloat = 0.0940
    /// 尾巴粗细
    static let tailWidth: CGFloat = 0.0880
    /// 尾巴起点（到圆心的半径，落在圆环内孔里）
    static let tailStart: CGFloat = 0.1100
    /// 尾巴终点（到圆心的半径，明显探出圆环，Q 才立得住）
    static let tailEnd: CGFloat = 0.3400

    /// 打包成 `drawQ` 需要的比例
    static var values: QProportions { (outerRadius, ringThickness, tailWidth, tailStart, tailEnd) }
}

/// 菜单栏图标专用的加重比例
///
/// 18pt 下按主图标比例画出来的圆环只有 ~1.8px，会糊成一团。
/// 这里把环和尾巴都加粗、整体收小留出呼吸空间，保证状态栏里依然认得出是 Q。
enum MenuMark {
    static let outerRadius: CGFloat = 0.3750
    static let ringThickness: CGFloat = 0.1250
    static let tailWidth: CGFloat = 0.1050
    static let tailStart: CGFloat = 0.1300
    static let tailEnd: CGFloat = 0.3800

    /// 打包成 `drawQ` 需要的比例
    static var values: QProportions { (outerRadius, ringThickness, tailWidth, tailStart, tailEnd) }
}

// MARK: - 颜色

/// 背景渐变：左上偏亮的石墨灰 → 右下偏暗的深灰
///
/// 刻意避开纯黑：纯黑在深色 Dock / 浅色壁纸上都会和系统 UI 糊在一起。
let backgroundTop = CGColor(srgbRed: 0.188, green: 0.188, blue: 0.204, alpha: 1)
let backgroundBottom = CGColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1)

/// 字标白色
let markWhite = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1)

/// 菜单栏模板图标用纯黑：template image 由系统按菜单栏明暗反色
let markTemplate = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

// MARK: - 绘制

/// 建一个 RGBA 位图上下文
///
/// - Parameter opaque: `true` 时背景不透明（App 图标），`false` 时留透明底（分层源图）
/// - Returns: 尺寸为 `canvas` 的绘图上下文
func makeContext(opaque: Bool) -> CGContext {
    let bitmapInfo = opaque
        ? CGImageAlphaInfo.noneSkipLast.rawValue
        : CGImageAlphaInfo.premultipliedLast.rawValue
    guard
        let context = CGContext(
            data: nil,
            width: Int(canvas),
            height: Int(canvas),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        fatalError("无法创建 \(Int(canvas))x\(Int(canvas)) 绘图上下文")
    }
    return context
}

/// 铺满斜向渐变底
///
/// CGContext 原点在左下角，所以 (0, height) 是左上、`(width, 0)` 是右下，
/// 渐变从左上亮处流向右下暗处，读起来像有光照方向。
func drawBackground(in context: CGContext) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [backgroundTop, backgroundBottom] as CFArray,
            locations: [0, 1]
        )
    else {
        fatalError("无法创建背景渐变")
    }
    context.saveGState()
    context.setFillColor(backgroundBottom)
    context.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    context.restoreGState()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: canvas),
        end: CGPoint(x: canvas, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

/// 画一个几何「Q」：粗圆环 + 右下角圆头尾巴
///
/// - Parameters:
///   - context: 目标上下文
///   - extent: 画布边长
///   - color: 字标颜色
///   - size: 字号比例（主图标传 `Mark`，菜单栏传 `MenuMark`）
func drawQ(
    in context: CGContext,
    extent: CGFloat,
    color: CGColor,
    size: (outerRadius: CGFloat, ringThickness: CGFloat, tailWidth: CGFloat, tailStart: CGFloat, tailEnd: CGFloat)
) {
    let center = CGPoint(x: extent / 2, y: extent / 2)
    let strokeWidth = size.ringThickness * extent
    let ringRadius = size.outerRadius * extent - strokeWidth / 2

    context.saveGState()
    context.setStrokeColor(color)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    context.setLineWidth(strokeWidth)
    context.addArc(
        center: center,
        radius: ringRadius,
        startAngle: 0,
        endAngle: .pi * 2,
        clockwise: false
    )
    context.strokePath()

    // 尾巴指向右下：CG 坐标 y 轴向上，所以角度取 -45°
    let diagonal = cos(CGFloat.pi / 4)
    let start = CGPoint(
        x: center.x + diagonal * size.tailStart * extent,
        y: center.y - diagonal * size.tailStart * extent
    )
    let end = CGPoint(
        x: center.x + diagonal * size.tailEnd * extent,
        y: center.y - diagonal * size.tailEnd * extent
    )
    context.setLineWidth(size.tailWidth * extent)
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()

    context.restoreGState()
}

// MARK: - 输出

/// 把 CGFloat 压成 SVG 里的小数（去掉多余尾零）
///
/// - Parameter value: 待格式化的数值
/// - Returns: 最多三位小数、无尾零的字符串
func svgNumber(_ value: CGFloat) -> String {
    var text = String(format: "%.3f", Double(value))
    while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
        text.removeLast()
    }
    return text
}

/// 生成矢量字标层（SVG），交给 Icon Composer 当玻璃图层
///
/// 用矢量而不是位图：字标是纯几何形状，缩放任意尺寸都不糊。
/// 画布保持整块方形、不留圆角、不烘焙高光与投影 —— 形状遮罩和玻璃质感都由系统负责。
///
/// - Returns: SVG 文本
func makeMarkSVG() -> String {
    let center = canvas / 2
    let strokeWidth = Mark.ringThickness * canvas
    let ringRadius = Mark.outerRadius * canvas - strokeWidth / 2
    let tailWidth = Mark.tailWidth * canvas
    // SVG 坐标 y 轴向下，45° 方向自然指向右下
    let diagonal = cos(CGFloat.pi / 4)
    let startOffset = diagonal * Mark.tailStart * canvas
    let endOffset = diagonal * Mark.tailEnd * canvas

    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(canvas))" height="\(Int(canvas))" \
    viewBox="0 0 \(Int(canvas)) \(Int(canvas))">
      <g fill="none" stroke="#FFFFFF" stroke-linecap="round">
        <circle cx="\(svgNumber(center))" cy="\(svgNumber(center))" \
    r="\(svgNumber(ringRadius))" stroke-width="\(svgNumber(strokeWidth))"/>
        <line x1="\(svgNumber(center + startOffset))" y1="\(svgNumber(center + startOffset))" \
    x2="\(svgNumber(center + endOffset))" y2="\(svgNumber(center + endOffset))" \
    stroke-width="\(svgNumber(tailWidth))"/>
      </g>
    </svg>

    """
}

/// 把图像编码成 PNG 并写到指定路径
///
/// - Parameters:
///   - image: 待写入的位图
///   - url: 目标文件路径
func writePNG(_ image: CGImage, to url: URL) throws {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        fatalError("PNG 编码失败：\(url.lastPathComponent)")
    }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url)
}

/// 仓库根目录（脚本必须从仓库根运行）
let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

/// 预览产物目录（不入库）
let outputDirectory = repositoryRoot.appendingPathComponent("icon-variants")

/// Icon Composer 图标的图层目录（入库，最终 App 图标从这里编译）
let iconBundleAssets = repositoryRoot.appendingPathComponent("Quick/AppIcon.icon/Assets")

/// 菜单栏模板图标的资产目录（入库）
let menuBarImageSet = repositoryRoot.appendingPathComponent("Quick/Assets.xcassets/MenuBarIcon.imageset")

/// 生成主图标：渐变底 + 白色 Q（这是给资产目录用的母版）
func makeMaster() -> CGImage {
    let context = makeContext(opaque: true)
    drawBackground(in: context)
    drawQ(in: context, extent: canvas, color: markWhite, size: Mark.values)
    return context.makeImage()!
}

/// 生成分层源图：背景层（不透明）
func makeBackgroundLayer() -> CGImage {
    let context = makeContext(opaque: true)
    drawBackground(in: context)
    return context.makeImage()!
}

/// 生成分层源图：字标层（透明底，只有白色 Q）
func makeMarkLayer() -> CGImage {
    let context = makeContext(opaque: false)
    drawQ(in: context, extent: canvas, color: markWhite, size: Mark.values)
    return context.makeImage()!
}

/// 生成菜单栏模板图标（纯黑 Q，透明底）
///
/// - Parameter pixels: 目标像素边长（18pt 的 1x / 2x）
/// - Returns: 透明底黑色 Q 位图
func makeMenuBarIcon(pixels: Int) -> CGImage {
    let extent = CGFloat(pixels)
    guard
        let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        fatalError("无法创建 \(pixels)x\(pixels) 菜单栏图标上下文")
    }
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    drawQ(in: context, extent: extent, color: markTemplate, size: MenuMark.values)
    return context.makeImage()!
}

// MARK: - 主流程

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

// 预览产物：不入库，只用来肉眼比对
try writePNG(makeMaster(), to: outputDirectory.appendingPathComponent("master.png"))
try writePNG(
    makeBackgroundLayer(),
    to: outputDirectory.appendingPathComponent("layer-00-background.png")
)
try writePNG(makeMarkLayer(), to: outputDirectory.appendingPathComponent("layer-01-mark.png"))

// 实际入库的两处成品
try makeMarkSVG().write(
    to: iconBundleAssets.appendingPathComponent("q.svg"),
    atomically: true,
    encoding: .utf8
)
try writePNG(makeMenuBarIcon(pixels: 18), to: menuBarImageSet.appendingPathComponent("menubar-18.png"))
try writePNG(
    makeMenuBarIcon(pixels: 36),
    to: menuBarImageSet.appendingPathComponent("menubar-18@2x.png")
)

print("✅ 图标已生成")
print("")
print("   App 图标（Liquid Glass）：")
print("     \(iconBundleAssets.appendingPathComponent("q.svg").path)")
print("     —— 由 Quick/AppIcon.icon 引用，构建时编译成全尺寸分层图标")
print("")
print("   菜单栏模板图标：")
print("     \(menuBarImageSet.path)/menubar-18.png（1x）")
print("     \(menuBarImageSet.path)/menubar-18@2x.png（2x）")
print("")
print("   预览产物（不入库）：\(outputDirectory.path)")
