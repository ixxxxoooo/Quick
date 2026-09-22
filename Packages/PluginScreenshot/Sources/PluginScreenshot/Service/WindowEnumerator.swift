// WindowEnumerator.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics
import Foundation

/// 枚举屏幕上可选的窗口
///
/// 用 `CGWindowListCopyWindowInfo`（同步）而不是 ScreenCaptureKit：遮罩里的悬停高亮
/// 每次鼠标移动都要命中一次，不能等一个 async 查询。真正抓图才走 SCK。
enum WindowEnumerator {

    /// 当前屏幕上、本 App 之外、正常的普通层窗口（前 → 后）
    static func selectableWindows(
        excludingPID pid: pid_t = ProcessInfo.processInfo.processIdentifier
    )
        -> [CaptureWindowInfo]
    {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        return raw.compactMap { info -> CaptureWindowInfo? in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID != pid else {
                return nil
            }
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else {
                return nil
            }
            let frame = CGRect(
                x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
            guard frame.width > 1, frame.height > 1 else { return nil }

            return CaptureWindowInfo(
                windowID: windowID,
                frame: frame,
                ownerName: info[kCGWindowOwnerName as String] as? String ?? "")
        }
    }

    /// 命中某个 CG 全局点（原点左上）下的最前窗口
    static func topWindow(at point: CGPoint, in windows: [CaptureWindowInfo]) -> CaptureWindowInfo? {
        windows.first { $0.frame.contains(point) }
    }
}
