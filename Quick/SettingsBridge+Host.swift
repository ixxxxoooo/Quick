// SettingsBridge+Host.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
import Foundation
import PluginLauncher
import PluginSystemControl
import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 宿主设置：超级面板、AI 基座、权限、关于
///
/// 从 `SettingsBridge.swift` 按设置页分区拆出，协议一致性仍声明在主类上。
extension SettingsBridge {

    // MARK: - 超级面板

    func makeSuperPanelSettingsView() -> AnyView {
        AnyView(SuperPanelSettingsView(dataSource: self))
    }

    var superPanelShortcutKeycaps: [String]? {
        core.hotKeyService.binding(for: CommandID.superPanel)?.keycaps
    }

    func setSuperPanelShortcut(keyCode: Int, carbonModifiers: Int) -> Bool {
        let shortcut = KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers)
        let outcome = core.hotKeyService.setBinding(shortcut, for: CommandID.superPanel, registerNow: true)
        if case .conflict = outcome { return false }
        return true
    }

    func clearSuperPanelShortcut() {
        core.hotKeyService.setBinding(nil, for: CommandID.superPanel, registerNow: false)
    }

    func clearRecentUsage() {
        core.usageHistory?.removeAll()
        log.notice("最近使用记录已清空")
    }

    // MARK: - AI 基座

    func makeAISettingsView() -> AnyView {
        AnyView(AISettingsPane(dataSource: self))
    }

    func testAIConnection() async -> SettingsAITestResult {
        do {
            let reply = try await AIService.testConnection()
            let snippet = reply.isEmpty ? "OK" : String(reply.prefix(40))
            log.notice("AI 连接测试成功")
            return SettingsAITestResult(isSuccess: true, message: "连接成功：\(snippet)")
        } catch {
            log.warning("AI 连接测试失败：\(error.localizedDescription, privacy: .public)")
            return SettingsAITestResult(
                isSuccess: false, message: error.localizedDescription)
        }
    }

    // MARK: - 权限

    /// 权限状态
    ///
    /// `canRequest` 的判定依据是「系统还会不会再弹框」：
    /// 未决定的可以申请，已经拒绝过的只能去系统设置里手动打开 ——
    /// 这时给一个「申请」按钮是骗人的，点了什么都不会发生。
    func permissionState(_ permission: SettingsPermission) -> SettingsPermissionState {
        switch permission {
        case .accessibility:
            let granted = core.permissionService.isAccessibilityGranted()
            return SettingsPermissionState(isGranted: granted, canRequest: !granted)

        case .screenCapture:
            let granted = core.permissionService.isScreenCaptureGranted()
            return SettingsPermissionState(isGranted: granted, canRequest: !granted)
        }
    }

    func requestPermission(_ permission: SettingsPermission) {
        log.notice("用户从设置页申请权限 \(permission.rawValue, privacy: .public)")
        switch permission {
        case .accessibility:
            core.permissionService.requestAccessibility()
        case .screenCapture:
            core.permissionService.requestScreenCapture()
        }
    }

    func openPermissionSettings(_ permission: SettingsPermission) {
        switch permission {
        case .accessibility:
            core.permissionService.openAccessibilitySettings()
        case .screenCapture:
            core.permissionService.openScreenCaptureSettings()
        }
    }

    // MARK: - 关于

    var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "—" }

    var panelGeometryDescription: String {
        "\(Int(DesignTokens.Size.panelWidth)) × \(Int(DesignTokens.Size.panelHeight)) · 圆角 \(Int(DesignTokens.Radius.panel))"
    }
}
