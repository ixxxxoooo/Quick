// CaptureEngine.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import CoreGraphics
import QuickCore
@preconcurrency import ScreenCaptureKit

/// 一个可被选中的窗口（原点左上，CG 全局坐标）
struct CaptureWindowInfo: Sendable, Equatable {
    let windowID: CGWindowID
    let frame: CGRect
    let ownerName: String
}

/// 截图引擎
///
/// 只负责「拿到干净的画面」：冻结全部显示器，或单独抓一个窗口。
/// 不做任何 UI，也不碰剪贴板/磁盘。
///
/// 全部在主 actor 上：ScreenCaptureKit 的调用本身是 `async` 的，不会阻塞主线程，
/// 而把 `CGImage`（非 `Sendable`）留在同一个隔离域里，才不用为它造跨 actor 的桥。
@MainActor
final class CaptureEngine {

    private let log = QuickLog.plugin(ScreenshotPlugin.id)

    /// 冻结全部显示器（排除本 App，避免把 Quick 自己的面板拍进去）
    func captureAllDisplays(excludingOwnApplication: Bool = true) async throws -> [DisplaySnapshot] {
        guard ScreenCapturePermission.isGranted else { throw CaptureError.permissionDenied }

        let content = try await shareableContent()
        let ownApplications =
            excludingOwnApplication
            ? content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            : []

        var snapshots: [DisplaySnapshot] = []
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.displayNotShareable(displayID)
            }
            snapshots.append(
                try await capture(screen: screen, display: display, excluding: ownApplications))
        }

        guard !snapshots.isEmpty else { throw CaptureError.noDisplays }
        log.notice("已冻结 \(snapshots.count, privacy: .public) 块显示器")
        return snapshots
    }

    /// 单独抓一个窗口（窗口截图用）
    func captureWindow(windowID: CGWindowID) async throws -> CGImage {
        guard ScreenCapturePermission.isGranted else { throw CaptureError.permissionDenied }

        let content = try await shareableContent()
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotCapturable(windowID)
        }

        let frame = window.frame
        let scale =
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }?
            .backingScaleFactor ?? 2

        let configuration = SCScreenshotConfiguration()
        configuration.width = max(1, Int((frame.width * scale).rounded()))
        configuration.height = max(1, Int((frame.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let output = try await SCScreenshotManager.captureScreenshot(
            contentFilter: filter, configuration: configuration)
        guard let image = output.sdrImage ?? output.hdrImage else {
            throw CaptureError.windowNotCapturable(windowID)
        }
        return image
    }

    // MARK: - 内部

    private func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
        } catch {
            log.error("SCShareableContent 失败：\(error.localizedDescription, privacy: .public)")
            throw CaptureError.noShareableContent(error.localizedDescription)
        }
    }

    private func capture(
        screen: NSScreen, display: SCDisplay, excluding applications: [SCRunningApplication]
    ) async throws -> DisplaySnapshot {
        let scale = screen.backingScaleFactor
        let configuration = SCScreenshotConfiguration()
        configuration.width = max(1, Int((screen.frame.width * scale).rounded()))
        configuration.height = max(1, Int((screen.frame.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr

        let filter = SCContentFilter(
            display: display, excludingApplications: applications, exceptingWindows: [])
        let output = try await SCScreenshotManager.captureScreenshot(
            contentFilter: filter, configuration: configuration)
        guard let image = output.sdrImage ?? output.hdrImage else {
            throw CaptureError.emptyImage(display.displayID)
        }

        return DisplaySnapshot(
            displayID: display.displayID,
            screenFrameInPoints: screen.frame,
            nominalScaleFactor: scale,
            image: image)
    }
}

/// 截图过程中可能出现的失败
enum CaptureError: Error, LocalizedError {
    case permissionDenied
    case noDisplays
    case displayNotShareable(CGDirectDisplayID)
    case windowNotCapturable(CGWindowID)
    case emptyImage(CGDirectDisplayID)
    case noShareableContent(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "没有屏幕录制权限"
        case .noDisplays: "没有可截取的显示器"
        case .displayNotShareable(let id): "显示器 \(id) 无法截取"
        case .windowNotCapturable(let id): "窗口 \(id) 无法截取"
        case .emptyImage(let id): "显示器 \(id) 返回了空画面"
        case .noShareableContent(let message): "无法读取屏幕内容：\(message)"
        }
    }
}

extension NSScreen {
    /// 显示器 id（`NSScreenNumber`）
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}
