// PinWindowController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// 贴图窗口控制器（参考 jietu 的 PinWindowController）
///
/// 把截图或剪贴板图片钉在屏幕上，作为一个可拖动的浮动窗口。
/// 支持拖动移动、Esc / ⌘W 关闭。多张可贴共存。
@MainActor
final class PinWindowController {
    private static var controllers: [PinWindowController] = []

    private let panel: PinPanel
    private let imageView: NSImageView
    private var monitor: Any?

    private let log = QuickLog.plugin("screenshot")

    /// 钉一张图片到桌面。多张可共存
    static func pin(image: NSImage, on screen: NSScreen? = nil) {
        let controller = PinWindowController(image: image, screen: screen)
        controllers.append(controller)
        // 必须 orderFrontRegardless：accessory 应用不在前台时，makeKeyAndOrderFront 经常看不见
        controller.panel.orderFrontRegardless()
        controller.panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.log.notice("贴图已显示，当前共 \(controllers.count, privacy: .public) 张")
    }

    private init(image: NSImage, screen: NSScreen?) {
        let target = screen ?? NSScreen.main
        let visible = target?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // 按原始大小显示，超过屏幕 80% 就等比缩小
        let imageSize = image.size
        let safeWidth = max(imageSize.width, 1)
        let safeHeight = max(imageSize.height, 1)
        let maxSize = CGSize(width: visible.width * 0.8, height: visible.height * 0.8)
        let scale = min(1, min(maxSize.width / safeWidth, maxSize.height / safeHeight))
        let size = CGSize(width: safeWidth * scale, height: safeHeight * scale)

        // 每多钉一张向右下错开，避免完全重叠
        let offset = CGFloat(PinWindowController.controllers.count % 6) * 24
        let origin = CGPoint(
            x: visible.midX - size.width / 2 + offset,
            y: visible.midY - size.height / 2 - offset
        )
        let frame = NSRect(origin: origin, size: size)

        imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true

        panel = PinPanel(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.contentView = imageView
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true

        // Esc / ⌘W 关闭当前 key 贴图
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
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
        panel.orderOut(nil)
        PinWindowController.controllers.removeAll { $0 === self }
        PinWindowController.controllers.last?.panel.makeKeyAndOrderFront(nil)
        log.notice("贴图已关闭，剩余 \(PinWindowController.controllers.count, privacy: .public) 张")
    }

    /// 关闭所有贴图（测试用）
    static func closeAllForTesting() {
        for controller in controllers {
            controller.close()
        }
    }

    /// 当前贴图数量（测试用）
    static var pinnedCountForTesting: Int { controllers.count }
}

/// 无边框但可成为 key 的贴图面板
///
/// 普通 `NSPanel` 默认 `canBecomeKey == false`，Esc / ⌘W 与拖动体验都会废掉。
private final class PinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
