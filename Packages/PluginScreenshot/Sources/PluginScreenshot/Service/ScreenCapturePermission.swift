// ScreenCapturePermission.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import CoreGraphics

/// 「屏幕录制」权限
///
/// 现读活值，不做启动时快照 —— 用户随时可能在系统设置里改。
enum ScreenCapturePermission {

    /// 当前是否已授权
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 弹一次系统授权（只会在还没决定时真正弹框）
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// 打开系统设置的「屏幕录制」页
    static func openSystemSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
