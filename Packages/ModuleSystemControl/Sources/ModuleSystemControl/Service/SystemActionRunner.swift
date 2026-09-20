// SystemActionRunner.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// 系统操作执行器
///
/// 通过 AppleScript 和系统 API 执行各种系统控制操作。
@MainActor
final class SystemActionRunner {

    private let log = QuickLog.module("systemcontrol")

    /// 执行系统操作
    /// - Parameter action: 要执行的操作
    func execute(_ action: SystemAction) {
        switch action {
        case .lockScreen:
            lockScreen()
        case .sleep:
            sleep()
        case .restart:
            runAppleScript("tell application \"System Events\" to restart")
        case .shutdown:
            runAppleScript("tell application \"System Events\" to shut down")
        case .logout:
            runAppleScript("tell application \"System Events\" to log out")
        case .screenSaver:
            startScreenSaver()
        case .emptyTrash:
            emptyTrash()
        case .ejectAll:
            ejectAll()
        case .toggleDarkMode:
            toggleDarkMode()
        case .toggleDoNotDisturb:
            EventBus.shared.post(ShowHUDEvent(message: "勿扰模式切换暂未实现", tone: .info))
        }
    }

    // MARK: - 具体操作实现

    private func lockScreen() {
        // 使用 CGSession 锁屏
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }

    private func sleep() {
        runAppleScript("tell application \"System Events\" to sleep")
    }

    private func startScreenSaver() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func emptyTrash() {
        runAppleScript(
            """
                tell application "Finder"
                    empty the trash
                end tell
            """)
        EventBus.shared.post(ShowHUDEvent(message: "废纸篓已清空", tone: .success))
    }

    private func ejectAll() {
        runAppleScript(
            """
                tell application "Finder"
                    eject (every disk whose ejectable is true)
                end tell
            """)
        EventBus.shared.post(ShowHUDEvent(message: "已推出所有磁盘", tone: .success))
    }

    private func toggleDarkMode() {
        runAppleScript(
            """
                tell application "System Events"
                    tell appearance preferences
                        set dark mode to not dark mode
                    end tell
                end tell
            """)
        EventBus.shared.post(ShowHUDEvent(message: "已切换外观模式", tone: .success))
    }

    // MARK: - AppleScript 执行辅助

    /// 执行 AppleScript
    private func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            // 常见原因：未授予「自动化」权限，或目标应用（System Events / Finder）未响应。
            log.error("AppleScript 执行失败: \(error, privacy: .public)")
        }
    }
}
