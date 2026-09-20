// LaunchAtLogin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import ServiceManagement

/// 开机自启管理
///
/// 使用 ServiceManagement 框架管理应用的开机自启状态。
@MainActor
public final class LaunchAtLogin {

    public init() {}

    /// 当前是否已设置开机自启
    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 设置开机自启状态
    /// - Parameter enabled: 是否启用
    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[LaunchAtLogin] 设置开机自启失败: \(error.localizedDescription)")
        }
    }
}
