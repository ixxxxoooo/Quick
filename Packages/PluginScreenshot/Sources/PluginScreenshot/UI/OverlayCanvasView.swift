// OverlayCanvasView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// 遮罩画布上的最终动作
enum OverlayAction {
    case save
    case copy
    case pin
}

/// 冻结画面上的选区 + 就地标注画布
///
/// 坐标约定：本视图**不翻转**，局部坐标原点在左下（AppKit 默认），与 `Annotation`
/// 的几何量一致。换算到图像像素（原点左上）只发生在烘焙那一刻（`makeOutput`）。
final class OverlayCanvasView: NSView {

    // MARK: - 输入

    private let snapshot: DisplaySnapshot
    private let screen: NSScreen
    private let previewImage: NSImage
    /// 点尺度的底图，仅供实时预览的马赛克取样
    private let previewCGImage: CGImage

    /// 窗口截图模式：悬停高亮窗口，点击选中
    var isWindowMode = false

    // MARK: - 回调

    var onCancel: (() -> Void)?
    /// 产出最终图 + 动作；由协调器负责保存 / 复制 / 钉图
    var onDeliver: ((CGImage, OverlayAction) -> Void)?
    /// 请求把第一响应者要回画布（工具栏 / 文本框收工后）
    var onFocusRequest: (() -> Void)?

    // MARK: - 状态

    private var selection: CGRect?
    private var annotations: [Annotation] = []
    private var draft: Annotation?
    private var tool: AnnotationTool = .rectangle
    private var color: RGBAColor = .red
    private var lineWidth: CGFloat = 3
    private var counterValue = 1

    private var selectionOrigin: CGPoint?
    private var drawOrigin: CGPoint?
    private var hoveredWindow: CaptureWindowInfo?
    private var windows: [CaptureWindowInfo] = []

    private var toolbar: AnnotationToolbarView?
    private var textField: NSTextField?
    private var trackingArea: NSTrackingArea?

    private let log = QuickLog.plugin(ScreenshotPlugin.id)

    // MARK: - 初始化

    init(snapshot: DisplaySnapshot, screen: NSScreen) {
        self.snapshot = snapshot
        self.screen = screen
        previewCGImage = CaptureOutput.scaled(snapshot.image, to: snapshot.screenFrameInPoints.size)
        previewImage = NSImage(cgImage: snapshot.image, size: snapshot.screenFrameInPoints.size)
        super.init(frame: NSRect(origin: .zero, size: snapshot.screenFrameInPoints.size))
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
    }

    // MARK: - 追踪

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. 冻结画面
        previewImage.draw(in: bounds)

        // 2. 压暗，然后在选区处「挖洞」露出原图
        NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.42).setFill()
        NSBezierPath(rect: bounds).fill()

        if isWindowMode, let hovered = hoveredWindow, selection == nil {
            let rect = localRect(fromCGRect: hovered.frame)
            context.saveGState()
            context.clip(to: rect)
            previewImage.draw(in: bounds)
            context.restoreGState()
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 2
            path.stroke()
            drawWindowLabel(hovered, at: rect)
            return
        }

        if let selection {
            context.saveGState()
            context.clip(to: selection)
            previewImage.draw(in: bounds)
            context.restoreGState()

            // 3. 标注
            AnnotationRenderer.draw(annotations, in: context, baseImage: previewCGImage)
            if let draft {
                AnnotationRenderer.draw(draft, in: context, baseImage: previewCGImage)
            }

            drawSelectionBorder(selection)
            drawSizeLabel(selection)
        }
    }

    private func drawSelectionBorder(_ rect: CGRect) {
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1
        border.stroke()

        NSColor.controlAccentColor.setStroke()
        let accent = NSBezierPath(rect: rect)
        accent.lineWidth = 1
        accent.stroke()
    }

    private func drawSizeLabel(_ rect: CGRect) {
        let scale = snapshot.effectiveScale
        let text = "\(Int(rect.width * scale)) × \(Int(rect.height * scale))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = CGPoint(
            x: rect.minX,
            y: max(4, rect.minY - size.height - 6))
        let background = NSRect(
            x: origin.x, y: origin.y, width: size.width + 10, height: size.height + 4)
        NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(
            at: CGPoint(x: origin.x + 5, y: origin.y + 2), withAttributes: attributes)
    }

    private func drawWindowLabel(_ window: CaptureWindowInfo, at rect: CGRect) {
        guard !window.ownerName.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (window.ownerName as NSString).size(withAttributes: attributes)
        let origin = CGPoint(x: rect.minX, y: max(4, rect.minY - size.height - 8))
        let background = NSRect(
            x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 6)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5).fill()
        (window.ownerName as NSString).draw(
            at: CGPoint(x: origin.x + 6, y: origin.y + 3), withAttributes: attributes)
    }

    // MARK: - 坐标换算

    /// 主显示器高度：cg（原点主屏左上）↔ 画布局部 的翻转基准
    private var referenceHeight: CGFloat {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.screens.first?.frame.height ?? 0
    }

    /// 全局 CG 矩形（原点左上）→ 画布局部矩形（原点左下）
    private func localRect(fromCGRect rect: CGRect) -> CGRect {
        let bottomInAppKit = referenceHeight - rect.maxY
        return CGRect(
            x: rect.minX - screen.frame.minX,
            y: bottomInAppKit - screen.frame.minY,
            width: rect.width,
            height: rect.height)
    }

    private func normalized(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - 鼠标

    override func mouseDown(with event: NSEvent) {
        finishTextEditing()
        let point = convert(event.locationInWindow, from: nil)

        if isWindowMode, selection == nil {
            windows = WindowEnumerator.selectableWindows()
            if let window = WindowEnumerator.topWindow(at: cgPoint(from: point), in: windows) {
                selection = localRect(fromCGRect: window.frame)
                showToolbar()
            }
            needsDisplay = true
            return
        }

        if let selection, selection.insetBy(dx: -6, dy: -6).contains(point) {
            beginAnnotation(at: point)
            return
        }

        // 选区外 → 重新框选
        dismissToolbar()
        selection = nil
        annotations.removeAll()
        selectionOrigin = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let origin = selectionOrigin {
            selection = normalized(origin, point)
            needsDisplay = true
            return
        }

        // 笔迹类：把新点接到当前 draft 末尾，画出来才是一条连续轨迹
        switch draft?.kind {
        case .pen(let points):
            draft = Annotation(
                id: draft!.id, kind: .pen(points: points + [point]), color: color, lineWidth: lineWidth)
            needsDisplay = true
            return
        case .highlight(let points):
            draft = Annotation(
                id: draft!.id, kind: .highlight(points: points + [point]), color: color, lineWidth: lineWidth)
            needsDisplay = true
            return
        default:
            break
        }

        guard let selection, let drawOrigin else { return }
        let clamped = CGPoint(
            x: min(max(point.x, selection.minX), selection.maxX),
            y: min(max(point.y, selection.minY), selection.maxY))
        draft = makeAnnotation(tool: tool, from: drawOrigin, to: clamped)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if selectionOrigin != nil {
            selectionOrigin = nil
            if let rect = selection, rect.width >= 4, rect.height >= 4 {
                selection = rect
                showToolbar()
            } else {
                // 单击（几乎没拖动）：选中点下的窗口
                windows = WindowEnumerator.selectableWindows()
                if let window = WindowEnumerator.topWindow(at: cgPoint(from: point), in: windows) {
                    selection = localRect(fromCGRect: window.frame)
                    showToolbar()
                } else {
                    selection = nil
                }
            }
            needsDisplay = true
            return
        }

        if let draft {
            annotations.append(draft)
            self.draft = nil
            drawOrigin = nil
            needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard isWindowMode, selection == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if windows.isEmpty { windows = WindowEnumerator.selectableWindows() }
        let window = WindowEnumerator.topWindow(at: cgPoint(from: point), in: windows)
        if window?.windowID != hoveredWindow?.windowID {
            hoveredWindow = window
            needsDisplay = true
        }
    }

    /// 画布局部点 → 全局 CG 点（原点左上）
    private func cgPoint(from local: CGPoint) -> CGPoint {
        CGPoint(
            x: screen.frame.minX + local.x,
            y: referenceHeight - (screen.frame.minY + local.y))
    }

    // MARK: - 标注

    private func beginAnnotation(at point: CGPoint) {
        switch tool {
        case .select:
            break
        case .counter:
            annotations.append(
                Annotation(kind: .counter(center: point, value: counterValue), color: color))
            counterValue += 1
            needsDisplay = true
        case .text:
            beginTextEditing(at: point)
        case .pen:
            draft = Annotation(kind: .pen(points: [point]), color: color, lineWidth: lineWidth)
        case .highlight:
            draft = Annotation(kind: .highlight(points: [point]), color: color, lineWidth: lineWidth)
        default:
            drawOrigin = point
        }
    }

    private func makeAnnotation(tool: AnnotationTool, from: CGPoint, to: CGPoint) -> Annotation? {
        switch tool {
        case .rectangle:
            return Annotation(kind: .rectangle(normalized(from, to)), color: color, lineWidth: lineWidth)
        case .ellipse:
            return Annotation(kind: .ellipse(normalized(from, to)), color: color, lineWidth: lineWidth)
        case .arrow:
            return Annotation(kind: .arrow(from: from, to: to), color: color, lineWidth: lineWidth)
        case .mosaic:
            return Annotation(kind: .mosaic(normalized(from, to)), color: color, lineWidth: lineWidth)
        case .select, .text, .counter, .pen, .highlight:
            return nil
        }
    }

    // MARK: - 文字

    private func beginTextEditing(at point: CGPoint) {
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y - 12, width: 180, height: 26))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        field.textColor = NSColor(
            srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        field.placeholderString = "输入文字"
        field.target = self
        field.action = #selector(commitText)
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    @objc private func commitText() {
        finishTextEditing()
    }

    private func finishTextEditing() {
        guard let field = textField else { return }
        textField = nil
        field.delegate = nil
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !string.isEmpty {
            annotations.append(
                Annotation(
                    kind: .text(
                        origin: CGPoint(x: field.frame.minX, y: field.frame.minY),
                        string: string, fontSize: 18),
                    color: color))
        }
        field.removeFromSuperview()
        onFocusRequest?()
        needsDisplay = true
    }

    // MARK: - 工具栏

    private func showToolbar() {
        dismissToolbar()
        guard let selection else { return }
        let bar = AnnotationToolbarView(frame: .zero)
        bar.onTool = { [weak self] tool in self?.activate(tool) }
        bar.onColor = { [weak self] color in self?.color = color }
        bar.onLineWidth = { [weak self] width in self?.lineWidth = width }
        bar.onConfirm = { [weak self] in self?.deliver(.save) }
        bar.onCopy = { [weak self] in self?.deliver(.copy) }
        bar.onPin = { [weak self] in self?.deliver(.pin) }
        bar.onCancel = { [weak self] in self?.onCancel?() }
        bar.layoutSubtreeIfNeeded()
        let size = bar.fittingSize
        addSubview(bar)
        toolbar = bar
        positionToolbar(near: selection, size: size)
    }

    private func positionToolbar(near selection: CGRect, size: NSSize) {
        guard let toolbar else { return }
        let margin: CGFloat = 10
        var x = selection.minX
        x = min(max(margin, x), bounds.width - size.width - margin)
        var y = selection.minY - size.height - margin
        if y < margin {
            y = min(selection.maxY + margin, bounds.height - size.height - margin)
        }
        toolbar.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func dismissToolbar() {
        toolbar?.removeFromSuperview()
        toolbar = nil
    }

    private func activate(_ tool: AnnotationTool) {
        self.tool = tool
        if tool == .text { return }
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (flags, event.keyCode) {
        case ([], 53):  // Esc
            if textField != nil {
                textField?.stringValue = ""
                finishTextEditing()
            } else {
                onCancel?()
            }
        case ([], 36), ([], 76):  // Return / Enter
            deliver(.save)
        case (.command, 8):  // ⌘C
            deliver(.copy)
        case (.command, 1):  // ⌘S
            deliver(.save)
        case (.command, 2):  // ⌘D
            deliver(.pin)
        case (.command, 6):  // ⌘Z
            if !annotations.isEmpty {
                annotations.removeLast()
                needsDisplay = true
            }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - 产出

    /// 全屏截图入口：一上来就把整块屏框好
    func preselectFullScreen() {
        selection = bounds
        showToolbar()
        needsDisplay = true
    }

    private func deliver(_ action: OverlayAction) {
        guard let image = makeOutput() else { return }
        onDeliver?(image, action)
    }

    /// 裁剪 + 烘焙出最终像素图
    private func makeOutput() -> CGImage? {
        finishTextEditing()
        guard let selection, selection.width >= 1, selection.height >= 1 else { return nil }
        guard let base = CaptureOutput.crop(snapshot, toLocalRect: selection) else { return nil }

        let scale = snapshot.effectiveScale
        let transformed = annotations.map {
            $0.transformed(offset: selection.origin, scale: scale)
        }
        return CaptureOutput.flatten(base: base, annotations: transformed)
    }

    // MARK: - 选区尺寸（测试钩子）

    #if DEBUG
        var debugSelection: CGRect? { selection }
    #endif
}

extension OverlayCanvasView: NSTextFieldDelegate {
    /// 焦点离开文本框（点别处、Tab 等）：把已输入的文字落成一条标注
    func controlTextDidEndEditing(_ obj: Notification) {
        finishTextEditing()
    }
}
