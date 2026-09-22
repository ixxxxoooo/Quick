// OverlayWindowController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit

/// 一块显示器上的遮罩窗 + 它的画布
@MainActor
final class OverlayWindowController {

    let window: OverlayWindow
    let snapshot: DisplaySnapshot
    let screen: NSScreen
    private let canvas: OverlayCanvasView

    var screenFrame: CGRect { window.frame }

    var onCancel: (() -> Void)? {
        get { canvas.onCancel }
        set { canvas.onCancel = newValue }
    }

    var onDeliver: ((CGImage, OverlayAction) -> Void)? {
        get { canvas.onDeliver }
        set { canvas.onDeliver = newValue }
    }

    var isWindowMode: Bool {
        get { canvas.isWindowMode }
        set { canvas.isWindowMode = newValue }
    }

    init(snapshot: DisplaySnapshot, screen: NSScreen, windowMode: Bool) {
        self.snapshot = snapshot
        self.screen = screen
        canvas = OverlayCanvasView(snapshot: snapshot, screen: screen)
        canvas.isWindowMode = windowMode

        // 先建零尺寸再 setFrame：直接给 screen.frame 在缩放/副屏上会被 AppKit 二次换算
        window = OverlayWindow(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        window.setFrame(screen.frame, display: false)
        window.contentView = canvas
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isMovable = false
        window.animationBehavior = .none
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.acceptsMouseMovedEvents = true
        window.hidesOnDeactivate = false

        canvas.onFocusRequest = { [weak self] in self?.focus() }
    }

    func show() {
        window.orderFrontRegardless()
        window.makeKey()
        canvas.needsDisplay = true
        focus()
    }

    func focus() {
        window.makeKey()
        window.makeFirstResponder(canvas)
    }

    /// 全屏截图入口：整块屏预先框好
    func preselectFullScreen() {
        canvas.preselectFullScreen()
    }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
    }
}
