// AnnotationToolbarView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickUI

/// 选区旁的就地标注工具栏
///
/// 用 AppKit 而不是 SwiftUI：它长在遮罩画布（`NSView`）之上，需要与画布共享同一套
/// 命中与坐标，混入一个 `NSHostingView` 只会让鼠标事件与第一响应者变得难以推理。
///
/// **主题**：玻璃材质（`NSGlassEffectView`）+ 语义色（`labelColor` / `controlAccentColor`），
/// 外观跟随 `NSApp.appearance`（遮罩窗口没有自己的 `appearance`，会继承应用级设置）。
/// 此前写死的深色底 + 白色图标在浅色主题下像一块外来物。
///
/// **不抢焦点**：所有按钮都是不接受第一响应者的轻量视图，点击后键盘仍留在画布上，
/// 所以 Esc / ⏎ / ⌘Z 在点过工具栏之后照样有效。
final class AnnotationToolbarView: NSView {

    // MARK: - 回调

    var onTool: ((AnnotationTool) -> Void)?
    var onColor: ((RGBAColor) -> Void)?
    var onLineWidth: ((CGFloat) -> Void)?
    var onUndo: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onCopy: (() -> Void)?
    var onPin: (() -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - 状态

    private(set) var tool: AnnotationTool = AnnotationDefaults.tool
    private(set) var color: RGBAColor = AnnotationDefaults.color
    private(set) var lineWidth: CGFloat = AnnotationDefaults.lineWidth

    // MARK: - 子视图

    private let glass = NSGlassEffectView()
    /// 玻璃的内容视图：自己持有内边距。`NSStackView.edgeInsets` 在玻璃里只有水平方向生效，
    /// 竖直方向会被玻璃按自身尺寸压平，所以内边距用约束而不是 stack 属性
    private let content = NSView()
    private let stack = NSStackView()
    private var toolButtons: [AnnotationTool: ToolbarButton] = [:]
    private var colorButtons: [ToolbarButton] = []
    private var widthButtons: [ToolbarButton] = []
    private let undoButton = ToolbarButton(content: .symbol("arrow.uturn.backward"))

    /// 工具栏上的工具顺序；序号即数字键 1…8
    static let toolOrder: [AnnotationTool] = [
        .rectangle, .ellipse, .arrow, .pen, .highlight, .text, .mosaic, .counter
    ]

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    // MARK: - 对外

    /// 画布侧切换了工具（数字键）：只同步高亮，不再回调
    func select(tool newTool: AnnotationTool) {
        guard Self.toolOrder.contains(newTool) else { return }
        tool = newTool
        updateToolSelection()
    }

    /// 有没有可撤销的标注；没有时撤销按钮置灰
    func setCanUndo(_ canUndo: Bool) {
        undoButton.isEnabled = canUndo
    }

    // MARK: - 布局

    /// 玻璃自己不报告内容尺寸，由内容视图的约束决定
    override var fittingSize: NSSize { content.fittingSize }

    /// 胶囊形：圆角随高度走，而不是写死一个会在缩放档位下失真的值
    override func layout() {
        super.layout()
        glass.cornerRadius = bounds.height / 2
    }

    // MARK: - 构建

    private func build() {
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let tokens = DesignTokens.ScreenshotToolbar.self
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = tokens.itemSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: tokens.insets.left),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -tokens.insets.right),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: tokens.insets.top),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -tokens.insets.bottom)
        ])
        glass.contentView = content

        // 工具
        for (index, candidate) in Self.toolOrder.enumerated() {
            let button = ToolbarButton(content: .symbol(candidate.symbolName))
            button.toolTip = "\(candidate.title)  \(index + 1)"
            button.setAccessibilityLabel(candidate.title)
            button.onClick = { [weak self] in
                self?.tool = candidate
                self?.updateToolSelection()
                self?.onTool?(candidate)
            }
            toolButtons[candidate] = button
            stack.addArrangedSubview(button)
        }
        addGroupBreak()

        // 颜色
        for swatch in RGBAColor.palette {
            let button = ToolbarButton(content: .swatch(swatch))
            button.setAccessibilityLabel("颜色")
            button.onClick = { [weak self] in
                self?.color = swatch
                self?.updateColorSelection()
                self?.onColor?(swatch)
            }
            colorButtons.append(button)
            stack.addArrangedSubview(button)
        }
        addGroupBreak()

        // 线宽：三个大小递增的圆点
        let diameters = DesignTokens.ScreenshotToolbar.widthDotDiameters
        for (index, width) in AnnotationDefaults.lineWidths.enumerated() {
            let button = ToolbarButton(
                content: .dot(diameters.indices.contains(index) ? diameters[index] : diameters.last ?? 0))
            button.toolTip = "线宽 \(Int(width))"
            button.setAccessibilityLabel("线宽 \(Int(width))")
            button.onClick = { [weak self] in
                self?.lineWidth = width
                self?.updateWidthSelection()
                self?.onLineWidth?(width)
            }
            widthButtons.append(button)
            stack.addArrangedSubview(button)
        }
        addGroupBreak()

        // 撤销 + 交付
        undoButton.toolTip = "撤销  ⌘Z"
        undoButton.setAccessibilityLabel("撤销")
        undoButton.isEnabled = false
        undoButton.onClick = { [weak self] in self?.onUndo?() }
        stack.addArrangedSubview(undoButton)

        stack.addArrangedSubview(
            makeAction("doc.on.doc", label: "复制", tip: "复制  ⌘C") { [weak self] in self?.onCopy?() })
        stack.addArrangedSubview(
            makeAction("pin", label: "钉在桌面", tip: "钉在桌面  ⌘D") { [weak self] in self?.onPin?() })
        stack.addArrangedSubview(
            makeAction("checkmark", label: "保存", tip: "保存  ⏎") { [weak self] in self?.onConfirm?() })
        stack.addArrangedSubview(
            makeAction("xmark", label: "取消", tip: "取消  Esc") { [weak self] in self?.onCancel?() })

        updateToolSelection()
        updateColorSelection()
        updateWidthSelection()
    }

    private func makeAction(
        _ symbol: String, label: String, tip: String, action: @escaping () -> Void
    ) -> ToolbarButton {
        let button = ToolbarButton(content: .symbol(symbol))
        button.toolTip = tip
        button.setAccessibilityLabel(label)
        button.onClick = action
        return button
    }

    /// 组与组之间：留白 + 一条细分隔线 + 留白
    private func addGroupBreak() {
        let gap = DesignTokens.ScreenshotToolbar.groupSpacing
        if let last = stack.arrangedSubviews.last {
            stack.setCustomSpacing(gap, after: last)
        }
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: DesignTokens.ScreenshotToolbar.separatorHeight)
            .isActive = true
        stack.addArrangedSubview(line)
        stack.setCustomSpacing(gap, after: line)
    }

    // MARK: - 选中态

    private func updateToolSelection() {
        for (candidate, button) in toolButtons { button.isSelected = candidate == tool }
    }

    private func updateColorSelection() {
        for (index, button) in colorButtons.enumerated() {
            button.isSelected = RGBAColor.palette[index] == color
        }
    }

    private func updateWidthSelection() {
        for (index, button) in widthButtons.enumerated() {
            button.isSelected = AnnotationDefaults.lineWidths[index] == lineWidth
        }
    }
}

// MARK: - 按钮

/// 工具栏里的一个按钮：图标 / 色块 / 圆点
///
/// 自己处理鼠标而不继承 `NSButton`：`NSButton` 的选中 / 悬停底板要靠 cell 绘制，
/// 难以与语义色、玻璃材质协调；这里 `draw(_:)` 在视图当前的 `effectiveAppearance`
/// 下执行，动态色（`labelColor`、`controlAccentColor`）会随主题自动解析。
final class ToolbarButton: NSView {

    enum Content {
        case symbol(String)
        case swatch(RGBAColor)
        case dot(CGFloat)
    }

    var onClick: (() -> Void)?

    var isSelected = false { didSet { refresh() } }
    var isEnabled = true {
        didSet {
            refresh()
            alphaValue = isEnabled ? 1 : DesignTokens.ScreenshotToolbar.disabledAlpha
        }
    }

    private let content: Content
    private var isHovered = false { didSet { refresh() } }
    private var isPressed = false { didSet { refresh() } }
    private let imageView = NSImageView()

    init(content: Content) {
        self.content = content
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let tokens = DesignTokens.ScreenshotToolbar.self
        let size: CGSize
        switch content {
        case .symbol:
            size = tokens.buttonSize
            let config = NSImage.SymbolConfiguration(pointSize: tokens.iconPointSize, weight: .medium)
            if case .symbol(let name) = content {
                imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
            }
            imageView.imageScaling = .scaleNone
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        case .swatch, .dot:
            size = CGSize(width: tokens.smallButton, height: tokens.smallButton)
        }
        widthAnchor.constraint(equalToConstant: size.width).isActive = true
        heightAnchor.constraint(equalToConstant: size.height).isActive = true

        setAccessibilityRole(.button)
        updateTint()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    // MARK: 状态

    private func refresh() {
        updateTint()
        needsDisplay = true
    }

    /// 选中：强调色底板 + 白图标；否则图标走 `labelColor`
    private func updateTint() {
        guard case .symbol = content else { return }
        imageView.contentTintColor = isSelected ? .white : .labelColor
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        let tokens = DesignTokens.ScreenshotToolbar.self
        let pill = NSBezierPath(
            roundedRect: bounds, xRadius: tokens.pillRadius, yRadius: tokens.pillRadius)

        // 底板：选中的图标工具用强调色；其余只在悬停 / 按下时出现
        switch content {
        case .symbol, .dot:
            if isSelected {
                NSColor.controlAccentColor.setFill()
                pill.fill()
            } else if isPressed && isEnabled {
                NSColor.labelColor.withAlphaComponent(tokens.pressedFill).setFill()
                pill.fill()
            } else if isHovered && isEnabled {
                NSColor.labelColor.withAlphaComponent(tokens.hoverFill).setFill()
                pill.fill()
            }
        case .swatch:
            if isHovered && isEnabled && !isSelected {
                NSColor.labelColor.withAlphaComponent(tokens.hoverFill).setFill()
                pill.fill()
            }
        }

        switch content {
        case .symbol:
            break  // 图标由 imageView 画
        case .dot(let diameter):
            (isSelected ? NSColor.white : NSColor.labelColor).setFill()
            NSBezierPath(ovalIn: centered(diameter)).fill()
        case .swatch(let swatch):
            drawSwatch(swatch)
        }
    }

    /// 色块：实心圆 + 一圈细轮廓（白 / 黑色块在玻璃上否则会隐没）；选中时外加一圈 `labelColor` 外环
    private func drawSwatch(_ swatch: RGBAColor) {
        let tokens = DesignTokens.ScreenshotToolbar.self
        let fillRect = centered(tokens.swatchDiameter)
        let fill = NSColor(
            srgbRed: swatch.red, green: swatch.green, blue: swatch.blue, alpha: swatch.alpha)
        fill.setFill()
        let dot = NSBezierPath(ovalIn: fillRect)
        dot.fill()
        NSColor.labelColor.withAlphaComponent(tokens.swatchStroke).setStroke()
        dot.lineWidth = 1
        dot.stroke()

        if isSelected {
            let ring = NSBezierPath(
                ovalIn: fillRect.insetBy(dx: -tokens.swatchRingGap, dy: -tokens.swatchRingGap))
            NSColor.labelColor.setStroke()
            ring.lineWidth = tokens.swatchRingWidth
            ring.stroke()
        }
    }

    private func centered(_ diameter: CGFloat) -> NSRect {
        NSRect(
            x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2,
            width: diameter, height: diameter)
    }

    // MARK: 鼠标

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// 点工具栏按钮不应把窗口拖动或把焦点带走
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        guard isEnabled, wasPressed else { return }
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) { onClick?() }
    }
}
