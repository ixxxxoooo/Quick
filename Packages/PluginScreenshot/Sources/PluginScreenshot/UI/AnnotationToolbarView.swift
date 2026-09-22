// AnnotationToolbarView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit

/// 选区旁的就地标注工具栏
///
/// 用 AppKit 而不是 SwiftUI：它长在遮罩画布（`NSView`）之上，需要与画布共享同一套
/// 命中与坐标，混入一个 `NSHostingView` 只会让鼠标事件与第一响应者变得难以推理。
final class AnnotationToolbarView: NSView {

    // MARK: - 回调

    var onTool: ((AnnotationTool) -> Void)?
    var onColor: ((RGBAColor) -> Void)?
    var onLineWidth: ((CGFloat) -> Void)?
    var onConfirm: (() -> Void)?
    var onCopy: (() -> Void)?
    var onPin: (() -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - 状态

    private(set) var tool: AnnotationTool = .rectangle
    private(set) var color: RGBAColor = .red
    private(set) var lineWidth: CGFloat = 3

    // MARK: - 子视图

    private let stack = NSStackView()
    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var colorButtons: [NSButton] = []
    private var widthControl = NSSegmentedControl()

    private static let toolOrder: [AnnotationTool] = [
        .rectangle, .ellipse, .arrow, .pen, .highlight, .text, .mosaic, .counter
    ]
    private static let widths: [CGFloat] = [2, 4, 7]

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 0.92).cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12).cgColor
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    // MARK: - 构建

    private func build() {
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        for tool in Self.toolOrder {
            let button = makeIconButton(
                tool.symbolName, tooltip: tool.title, action: #selector(toolTapped(_:)))
            button.tag = Self.toolOrder.firstIndex(of: tool) ?? 0
            toolButtons[tool] = button
            stack.addArrangedSubview(button)
        }

        stack.addArrangedSubview(separator())

        for color in RGBAColor.palette {
            let button = makeColorButton(color)
            colorButtons.append(button)
            stack.addArrangedSubview(button)
        }

        stack.addArrangedSubview(separator())

        widthControl.segmentCount = Self.widths.count
        widthControl.segmentStyle = .texturedRounded
        widthControl.trackingMode = .selectOne
        widthControl.target = self
        widthControl.action = #selector(widthChanged)
        for (index, width) in Self.widths.enumerated() {
            widthControl.setLabel("\(Int(width))", forSegment: index)
        }
        widthControl.selectedSegment = 1
        stack.addArrangedSubview(widthControl)

        stack.addArrangedSubview(separator())

        stack.addArrangedSubview(
            makeIconButton("doc.on.doc", tooltip: "复制", action: #selector(copyTapped)))
        stack.addArrangedSubview(makeIconButton("pin", tooltip: "钉在桌面", action: #selector(pinTapped)))
        stack.addArrangedSubview(
            makeIconButton("checkmark", tooltip: "保存", action: #selector(confirmTapped)))
        stack.addArrangedSubview(makeIconButton("xmark", tooltip: "取消", action: #selector(cancelTapped)))

        updateToolSelection()
    }

    private func separator() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return view
    }

    private func makeIconButton(_ symbol: String, tooltip: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        let button = NSButton(image: image ?? NSImage(), target: self, action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = .white
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    private func makeColorButton(_ color: RGBAColor) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(colorTapped(_:)))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.image = Self.swatchImage(color: color, selected: false)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 20).isActive = true
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true
        button.tag = RGBAColor.palette.firstIndex(of: color) ?? 0
        return button
    }

    // MARK: - 动作

    @objc private func toolTapped(_ sender: NSButton) {
        guard Self.toolOrder.indices.contains(sender.tag) else { return }
        tool = Self.toolOrder[sender.tag]
        updateToolSelection()
        onTool?(tool)
    }

    @objc private func colorTapped(_ sender: NSButton) {
        guard RGBAColor.palette.indices.contains(sender.tag) else { return }
        color = RGBAColor.palette[sender.tag]
        updateColorSelection()
        onColor?(color)
    }

    @objc private func widthChanged() {
        let index = max(0, min(Self.widths.count - 1, widthControl.selectedSegment))
        lineWidth = Self.widths[index]
        onLineWidth?(lineWidth)
    }

    @objc private func confirmTapped() { onConfirm?() }
    @objc private func copyTapped() { onCopy?() }
    @objc private func pinTapped() { onPin?() }
    @objc private func cancelTapped() { onCancel?() }

    // MARK: - 选中态

    private func updateToolSelection() {
        for (candidate, button) in toolButtons {
            button.contentTintColor = candidate == tool ? NSColor.controlAccentColor : .white
        }
    }

    private func updateColorSelection() {
        for button in colorButtons {
            let isSelected =
                RGBAColor.palette.indices.contains(button.tag)
                && RGBAColor.palette[button.tag] == color
            button.image = Self.swatchImage(color: RGBAColor.palette[button.tag], selected: isSelected)
        }
    }

    /// 生成一个圆形色块，选中时加一圈白环
    private static func swatchImage(color: RGBAColor, selected: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(ovalIn: selected ? rect.insetBy(dx: 2, dy: 2) : rect)
        NSColor(
            srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha
        ).setFill()
        path.fill()
        if selected {
            let ring = NSBezierPath(ovalIn: rect)
            ring.lineWidth = 2
            NSColor.white.setStroke()
            ring.stroke()
        }
        image.unlockFocus()
        return image
    }
}
