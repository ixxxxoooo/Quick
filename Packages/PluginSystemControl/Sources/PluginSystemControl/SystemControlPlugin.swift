// SystemControlPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 系统控制插件
///
/// 提供常用系统操作的快捷入口：锁屏、睡眠、重启、
/// 关机、清空废纸篓、弹出磁盘、屏幕保护程序等。
@MainActor
public final class SystemControlPlugin: QuickPlugin, PluginViewProviding {

    public static let id = "systemcontrol"
    public static let name = "系统控制"
    public static let icon = "power.circle.fill"
    public static let description = "macOS 系统级快捷指令聚合，支持锁定屏幕、睡眠、重启、关机、清空废纸篓与外观切换等操作。"
    public static let triggerWords = [
        "系统控制", "system control", "系统命令",
        "锁屏", "lock", "睡眠", "sleep", "重启", "restart", "关机", "shutdown",
        "屏保", "screensaver", "废纸篓", "trash", "弹出", "eject",
        "深色", "dark", "主题", "theme", "注销", "logout"
    ]

    public var isEnabled = true

    private let log = QuickLog.plugin(SystemControlPlugin.id)

    /// 系统操作运行器
    private let runner = SystemActionRunner()

    /// 用户设置存储（用于别名）
    private let settingsStore: SettingsStore?

    public init(settingsStore: SettingsStore? = nil) {
        self.settingsStore = settingsStore
    }

    /// 每条系统操作都是一条命令。锁屏作为空查询时的那一条入口
    public static var functionCommands: [CommandDescriptor] {
        SystemAction.allCases.map { action in
            CommandDescriptor(
                id: CommandID.systemAction(action.rawValue),
                pluginID: id,
                pluginName: name,
                title: action.title,
                subtitle: action.description,
                keywords: action.keywords,
                icon: action.icon,
                showsWhenQueryEmpty: false,
                aliasKey: "system.\(action.rawValue)"
            )
        }
    }

    /// 热键和搜索走同一个入口。命令关闭时直接拒绝
    public func perform(commandID: String) {
        let prefix = "systemcontrol."
        guard commandID.hasPrefix(prefix) else { return }
        let raw = String(commandID.dropFirst(prefix.count))
        guard let action = SystemAction(rawValue: raw) else { return }
        if let settingsStore, !settingsStore.isCommandEnabled(commandID) {
            log.notice("命令已关闭，拒绝执行 \(commandID, privacy: .public)")
            return
        }
        log.notice("执行系统命令 \(commandID, privacy: .public)")
        runner.execute(action)
        EventBus.shared.post(HidePaletteEvent())
    }

    /// 供外部直接调用执行指定系统操作（例如热键分发）
    public func execute(_ action: SystemAction) {
        runner.execute(action)
    }

    public func makeView() -> AnyView {
        AnyView(SystemControlView(runner: runner))
    }

    public func activate() {
        log.notice("插件已激活，可用系统操作 \(SystemAction.allCases.count, privacy: .public) 项")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
