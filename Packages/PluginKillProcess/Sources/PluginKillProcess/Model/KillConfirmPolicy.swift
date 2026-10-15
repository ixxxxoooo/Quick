// KillConfirmPolicy.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 结束进程前要不要二次确认
///
/// 纯逻辑，所以「哪些情况必须问」能被测试固定下来，而不是散落在按键处理里。
enum KillConfirmPolicy {

    /// 无论设置如何都必须确认的进程
    ///
    /// 杀掉它们等于把用户踢出会话或让界面整体卡死，不是「结束一个卡住的 App」。
    /// `Finder`、`Dock` 不在其列：它们被杀后系统会立刻拉起，是常见的有意操作。
    static let protectedNames: Set<String> = [
        "WindowServer", "loginwindow", "launchd", "kernel_task", "SystemUIServer"
    ]

    /// 是否需要确认
    ///
    /// - Parameters:
    ///   - force: 是否强制结束（SIGKILL，进程没有机会保存数据）
    ///   - processName: 目标进程名
    ///   - confirmForceKill: 设置里「强制结束前确认」的值
    static func needsConfirmation(
        force: Bool, processName: String, confirmForceKill: Bool
    ) -> Bool {
        if protectedNames.contains(processName) { return true }
        return force && confirmForceKill
    }

    /// 确认框的文案
    static func message(force: Bool, processName: String) -> String {
        if protectedNames.contains(processName) {
            return "「\(processName)」是系统核心进程，结束它可能让你被注销或界面卡死。"
        }
        return "强制结束「\(processName)」不会给它保存数据的机会，未保存的内容会丢失。"
    }
}
