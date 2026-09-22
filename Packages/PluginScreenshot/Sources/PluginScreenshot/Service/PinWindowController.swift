// PinWindowController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// 钉图：把截图钉在屏幕上，成为一个可拖动、可缩放的置顶窗口
///
/// 支持拖动移动、滚轮 / 捏合缩放、双击关闭、Esc / ⌘W 关闭、右键菜单。
/// 多张可共存。
@MainActor
final class PinWindowController {

    private static var controllers: [PinWindowController] = []

    private let window: PinPanel
    private let content: PinContentView
    private var monitor: Any?

    private let log = QuickLog.plugin(ScreenshotPlugin.id)

    /// 钉一张图
    /// - Parameter targetFrame: 指定屏幕坐标位置与大小（原地钉图）；nil 时按原始大小钉在屏幕中部
    static func pin(image: CGImage, on screen: NSScreen?, targetFrame: CGRect? = nil) {
        let controller = PinWindowController(image: image, screen: screen, targetFrame: targetFrame)
        controllers.append(controller)
        controller.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.log.notice("贴图已显示，当前共 \(controllers.count, privacy: .public) 张")
    }

    private init(image: CGImage, screen: NSScreen?, targetFrame: CGRect?) {
        let target = screen ?? NSScreen.main
        let visible = target?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let frame: NSRect
        if let targetFrame, targetFrame.width > 1, targetFrame.height > 1 {
            frame = targetFrame
        } else {
            // 按原始像素尺寸显示（除以屏幕缩放），超过可见区 90% 再等比缩小
            let backingScale = target?.backingScaleFactor ?? 2
            let natural = CGSize(
                width: CGFloat(image.width) / backingScale,
                height: CGFloat(image.height) / backingScale)
            let maxSize = CGSize(width: visible.width * 0.9, height: visible.height * 0.9)
            let scale = min(
                1, min(maxSize.width / max(natural.width, 1), maxSize.height / max(natural.height, 1)))
            let size = CGSize(width: natural.width * scale, height: natural.height * scale)
            let offset = CGFloat(PinWindowController.controllers.count % 6) * 24
            frame = NSRect(
                x: visible.midX - size.width / 2 + offset,
                y: visible.midY - size.height / 2 - offset,
                width: size.width, height: size.height)
        }

        content = PinContentView(frame: NSRect(origin: .zero, size: frame.size), image: image)
        window = PinPanel(
            contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)

        window.contentView = content
        window.initialFirstResponder = content
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true

        content.onRequestClose = { [weak self] in self?.close() }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window.isKeyWindow else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53 {
                self.close()
                return nil
            }
            if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
                self.close()
                return nil
            }
            return event
        }
    }

    private func close() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        window.orderOut(nil)
        PinWindowController.controllers.removeAll { $0 === self }
        PinWindowController.controllers.last?.window.makeKeyAndOrderFront(nil)
        log.notice("贴图已关闭，剩余 \(PinWindowController.controllers.count, privacy: .public) 张")
    }

    /// 测试用：收掉全部钉图
    static func closeAllForTesting() {
        for controller in controllers { controller.close() }
    }

    /// 测试用：当前钉图数量
    static var pinnedCountForTesting: Int { controllers.count }
}

/// 无边框但可成为 key 的钉图面板
private final class PinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
