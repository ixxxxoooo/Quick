// PinContentView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// 钉图的绘制与交互载体
///
/// 用自绘而不是 `NSImageView`：要自己区分「拖动移动」与「边缘缩放」，
/// 并让滚轮 / 捏合按比例改变窗口大小 —— 交给系统窗口拖拽会和这些手势打架。
final class PinContentView: NSView {

    let image: CGImage
    var onRequestClose: (() -> Void)?

    private let nsImage: NSImage
    private var dragStartMouse: CGPoint?
    private var dragStartOrigin: CGPoint?
    private var closeButton: NSButton?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    private let log = QuickLog.plugin(ScreenshotPlugin.id)

    init(frame: NSRect, image: CGImage) {
        self.image = image
        nsImage = NSImage(cgImage: image, size: frame.size)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.18).cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    override func draw(_ dirtyRect: NSRect) {
        nsImage.draw(in: bounds)
    }

    // MARK: - 悬停

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        if hovering {
            showCloseButton()
        } else {
            closeButton?.removeFromSuperview()
            closeButton = nil
        }
    }

    private func showCloseButton() {
        guard closeButton == nil else { return }
        let button = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭")
                ?? NSImage(),
            target: self, action: #selector(closeTapped))
        button.isBordered = false
        button.contentTintColor = .white
        button.frame = NSRect(x: bounds.maxX - 28, y: bounds.maxY - 28, width: 22, height: 22)
        button.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(button)
        closeButton = button
    }

    @objc private func closeTapped() { onRequestClose?() }

    // MARK: - 拖动

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onRequestClose?()
            return
        }
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startMouse = dragStartMouse, let startOrigin = dragStartOrigin,
            let window
        else { return }
        let current = NSEvent.mouseLocation
        window.setFrameOrigin(
            CGPoint(
                x: startOrigin.x + current.x - startMouse.x,
                y: startOrigin.y + current.y - startMouse.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragStartMouse = nil
        dragStartOrigin = nil
    }

    // MARK: - 缩放

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.1 else { return }
        scaleWindow(by: 1 + delta * 0.01)
    }

    override func magnify(with event: NSEvent) {
        scaleWindow(by: 1 + event.magnification)
    }

    /// 按比例缩放窗口（保持图片宽高比）
    private func scaleWindow(by factor: CGFloat) {
        guard let window, image.width > 0, image.height > 0 else { return }
        let aspect = CGFloat(image.height) / CGFloat(image.width)
        let current = window.frame
        var width = min(max(current.width * factor, 60), 4000)
        var height = (width * aspect).rounded()
        if height > 4000 {
            height = 4000
            width = (height / aspect).rounded()
        }

        // 以窗口中心为锚点缩放
        let center = CGPoint(x: current.midX, y: current.midY)
        let origin = CGPoint(x: center.x - width / 2, y: center.y - height / 2)
        window.setFrame(NSRect(origin: origin, size: CGSize(width: width, height: height)), display: true)
        nsImage.size = CGSize(width: width, height: height)
        needsDisplay = true
    }

    // MARK: - 菜单

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "复制图像", action: #selector(copyImage), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "关闭", action: #selector(closeTapped), keyEquivalent: "")
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func copyImage() {
        ScreenshotDelivery.copyToPasteboard(image)
    }
}
