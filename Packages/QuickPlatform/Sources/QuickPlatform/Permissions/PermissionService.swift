// PermissionService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import ApplicationServices
import CoreLocation

/// 定位权限的三态
///
/// 分成三态而不是一个 Bool：`notDetermined` 还能申请，`denied` 只能去系统设置里开，
/// 界面给的下一步动作不同。
public enum LocationPermissionStatus: Sendable {
    case notDetermined
    case granted
    case denied
}

/// 系统权限管理服务
///
/// 封装 macOS 各项系统权限的检查和申请。
/// 插件通过此服务检查所需权限状态，引导用户授权。
@MainActor
public final class PermissionService {

    public init() {}

    // MARK: - 辅助功能权限

    /// 检查辅助功能权限是否已授予
    /// - Returns: 是否已授权
    public func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 请求辅助功能权限（弹出系统授权对话框）
    public func requestAccessibility() {
        // kAXTrustedCheckOptionPrompt 是全局可变状态，需要在非隔离上下文中访问
        let prompt: CFString = "AXTrustedCheckOptionPrompt" as CFString
        let options = [prompt: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 屏幕录制权限（截图/窗口捕获需要）

    /// 检查屏幕录制权限
    /// - Returns: 是否已授权
    public func isScreenCaptureGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 请求屏幕录制权限
    public func requestScreenCapture() {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - 打开系统偏好设置

    /// 打开辅助功能设置面板
    public func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// 打开屏幕录制设置面板
    public func openScreenCaptureSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - 定位权限（天气插件按需使用）

    /// 查询定位权限状态
    ///
    /// **只读，不会弹系统权限框。** 创建一个 `CLLocationManager` 只是拿状态，
    /// 不触发任何申请；申请必须由用户的明确动作触发，见 `WeatherService`。
    ///
    /// - Returns: 定位权限的三态
    public func locationStatus() -> LocationPermissionStatus {
        switch CLLocationManager().authorizationStatus {
        case .authorized, .authorizedAlways:
            return .granted
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    /// 打开定位服务设置面板
    ///
    /// 只负责「带用户去开」，不负责申请：定位权限的申请必须由用户的明确动作触发，
    /// 见 `WeatherService` 的定位权限策略。
    public func openLocationSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
        NSWorkspace.shared.open(url)
    }
}
