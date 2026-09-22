// OverlayCoordinator.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// 截图遮罩的总控：冻结画面 → 每块屏一个遮罩 → 收结果 → 交付
///
/// 一次截图期间只有一份实例在跑；结束后把前台还给用户原来的 App。
@MainActor
final class OverlayCoordinator {

    private let log = QuickLog.plugin(ScreenshotPlugin.id)
    private let engine = CaptureEngine()

    private var controllers: [OverlayWindowController] = []
    private var escapeMonitor: Any?
    private var previousApplication: NSRunningApplication?

    var isPresenting: Bool { !controllers.isEmpty }

    /// 开始一次截图
    /// - Parameters:
    ///   - windowMode: 是否为「窗口截图」（悬停高亮、点击选窗）
    ///   - preselectFullScreen: 是否一上来就把整块屏框好（全屏截图入口）
    func begin(windowMode: Bool, preselectFullScreen: Bool = false) async {
        guard !isPresenting else { return }
        EventBus.shared.post(HidePaletteEvent(restoreFocus: false))
        try? await Task.sleep(for: .milliseconds(180))

        guard ScreenCapturePermission.isGranted else {
            ScreenCapturePermission.request()
            EventBus.shared.post(
                ShowHUDEvent(message: "需要「屏幕录制」权限，授权后请重启 Quick", tone: .warning))
            ScreenCapturePermission.openSystemSettings()
            return
        }

        let snapshots: [DisplaySnapshot]
        do {
            snapshots = try await engine.captureAllDisplays()
        } catch {
            log.error("冻结屏幕失败：\(error.localizedDescription, privacy: .public)")
            EventBus.shared.post(ShowHUDEvent(message: "截图失败：\(error.localizedDescription)", tone: .danger))
            return
        }

        previousApplication = NSWorkspace.shared.frontmostApplication
        for snapshot in snapshots {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == snapshot.displayID })
            else { continue }
            let controller = OverlayWindowController(
                snapshot: snapshot, screen: screen, windowMode: windowMode)
            controller.onCancel = { [weak self] in self?.finish() }
            controller.onDeliver = { [weak self] image, action in
                self?.deliver(image, action: action, screen: screen)
            }
            controllers.append(controller)
        }

        guard !controllers.isEmpty else {
            log.error("没有可用的遮罩窗")
            return
        }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresenting else { return event }
            if event.keyCode == 53 {
                self.finish()
                return nil
            }
            return event
        }

        NSApp.activate(ignoringOtherApps: true)
        for controller in controllers { controller.show() }

        let mouse = NSEvent.mouseLocation
        let focused = controllers.first { $0.screenFrame.contains(mouse) } ?? controllers.first
        focused?.focus()
        if preselectFullScreen { focused?.preselectFullScreen() }
        log.notice("截图遮罩已展开，共 \(self.controllers.count, privacy: .public) 块屏")
    }

    // MARK: - 交付

    private func deliver(_ image: CGImage, action: OverlayAction, screen: NSScreen) {
        switch action {
        case .save:
            let path = ScreenshotDelivery.deliver(image)
            finish()
            if path != nil {
                EventBus.shared.post(
                    ShowHUDEvent(message: "截图已保存到桌面", tone: .success))
            } else {
                EventBus.shared.post(ShowHUDEvent(message: "截图已复制到剪贴板", tone: .success))
            }

        case .copy:
            ScreenshotDelivery.copyToPasteboard(image)
            finish()
            EventBus.shared.post(ShowHUDEvent(message: "截图已复制到剪贴板", tone: .success))

        case .pin:
            PinWindowController.pin(image: image, on: screen, targetFrame: nil)
            finish()
            EventBus.shared.post(ShowHUDEvent(message: "已钉在桌面", tone: .success))
        }
    }

    // MARK: - 收尾

    private func finish() {
        guard isPresenting else { return }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        for controller in controllers { controller.close() }
        controllers.removeAll()

        if let previousApplication,
            previousApplication.bundleIdentifier != Bundle.main.bundleIdentifier
        {
            previousApplication.activate()
        }
        previousApplication = nil
    }

    /// 直接钉一张已有图片（贴图入口）
    func pinExistingImage() {
        guard let image = ScreenshotDelivery.imageFromPasteboard() else {
            EventBus.shared.post(ShowHUDEvent(message: "剪贴板里没有可贴的图片", tone: .warning))
            return
        }
        PinWindowController.pin(image: image, on: NSScreen.main, targetFrame: nil)
        EventBus.shared.post(ShowHUDEvent(message: "已钉在桌面", tone: .success))
    }
}
