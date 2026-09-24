// SystemActionRunner.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// 系统操作执行器
///
/// 通过 AppleScript 和系统 API 执行各种系统控制操作。
///
/// ## 反馈必须如实
///
/// 这些操作大多走 AppleScript，而 AppleScript 要「自动化」权限 —— 它按代码签名授予，
/// 每重新构建一次 dev 版就可能失效。所以 `runAppleScript` **返回**执行结果，调用方按结果
/// 说话：不做「不管成没成都弹一条成功提示」这种事，那会让用户以为功能坏了却看不出原因。
/// 自动化类操作的失败提示文案（单测可钉住格式）
enum SystemActionAutomationCopy: Sendable {
    static func permissionHint(action: String) -> String {
        "\(action)失败：需要「自动化」权限"
    }
}

@MainActor
final class SystemActionRunner {

    private let log = QuickLog.plugin("systemcontrol")

    /// 执行系统操作
    /// - Parameter action: 要执行的操作
    func execute(_ action: SystemAction) {
        switch action {
        case .lockScreen:
            lockScreen()
        case .sleep:
            reportFailure(
                runAppleScript("tell application \"System Events\" to sleep", what: "睡眠"),
                what: "睡眠")
        case .restart:
            reportFailure(
                runAppleScript("tell application \"System Events\" to restart", what: "重新启动"),
                what: "重新启动")
        case .shutdown:
            reportFailure(
                runAppleScript("tell application \"System Events\" to shut down", what: "关机"),
                what: "关机")
        case .logout:
            reportFailure(
                runAppleScript("tell application \"System Events\" to log out", what: "退出登录"),
                what: "退出登录")
        case .screenSaver:
            startScreenSaver()
        case .emptyTrash:
            emptyTrash()
        case .ejectAll:
            ejectAll()
        case .toggleDarkMode:
            toggleDarkMode()
        }
    }

    // MARK: - 具体操作实现

    private func lockScreen() {
        // 让显示器立刻休眠；是否要求密码由「系统设置 → 锁屏」决定
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        do {
            try task.run()
        } catch {
            log.error("锁定屏幕失败：\(error.localizedDescription, privacy: .public)")
            EventBus.shared.post(ShowHUDEvent(message: "锁定屏幕失败", tone: .warning))
        }
    }

    private func startScreenSaver() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func emptyTrash() {
        report(
            runAppleScript(
                """
                tell application "Finder"
                    empty the trash
                end tell
                """, what: "清空废纸篓"),
            done: "废纸篓已清空")
    }

    private func ejectAll() {
        report(
            runAppleScript(
                """
                tell application "Finder"
                    eject (every disk whose ejectable is true)
                end tell
                """, what: "推出所有磁盘"),
            done: "已推出所有磁盘")
    }

    private func toggleDarkMode() {
        report(
            runAppleScript(
                """
                tell application "System Events"
                    tell appearance preferences
                        set dark mode to not dark mode
                    end tell
                end tell
                """, what: "切换深色模式"),
            done: "已切换深色模式")
    }

    // MARK: - AppleScript 执行辅助

    /// 执行 AppleScript
    ///
    /// - Parameters:
    ///   - source: 脚本源码
    ///   - what: 出问题时报出来的动作名（日志里要看得出是哪一步）
    /// - Returns: 是否真的执行成功
    @discardableResult
    private func runAppleScript(_ source: String, what: String) -> Bool {
        guard let script = NSAppleScript(source: source) else {
            log.error("\(what, privacy: .public)的 AppleScript 编译失败")
            return false
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard let error else { return true }

        // 最常见的原因是没给「自动化」权限（脚本源码写错会在上面就返回 false）。
        log.error("\(what, privacy: .public)失败：\(error, privacy: .public)")
        return false
    }

    /// 成败都给一句话
    private func report(_ succeeded: Bool, done: String) {
        guard succeeded else {
            EventBus.shared.post(
                ShowHUDEvent(
                    message: SystemActionAutomationCopy.permissionHint(action: done),
                    tone: .warning))
            return
        }
        EventBus.shared.post(ShowHUDEvent(message: done, tone: .success))
    }

    /// 只在失败时说话
    ///
    /// 成功时机器已经睡了 / 重启了 / 注销了，没有机会再显示 HUD。
    private func reportFailure(_ succeeded: Bool, what: String) {
        guard !succeeded else { return }
        EventBus.shared.post(
            ShowHUDEvent(
                message: SystemActionAutomationCopy.permissionHint(action: what),
                tone: .warning))
    }
}
