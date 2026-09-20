// LaunchAtLogin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import ServiceManagement

/// 开机自启管理
///
/// 使用 ServiceManagement 框架管理应用的开机自启状态。
@MainActor
public final class LaunchAtLogin {

    private let log = QuickLog.platform

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
            log.notice("开机自启已\(enabled ? "启用" : "停用", privacy: .public)")
        } catch {
            // 常见原因：应用不在 /Applications 下，或用户已在「登录项」里手动关闭。
            log.error(
                """
                设置开机自启失败（enabled=\(enabled, privacy: .public)）：\
                \(error.localizedDescription, privacy: .public)
                """)
        }
    }
}
