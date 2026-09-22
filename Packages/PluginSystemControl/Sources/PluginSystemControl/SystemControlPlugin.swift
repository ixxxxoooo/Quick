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
public final class SystemControlPlugin: QuickPlugin {

    public static let id = "systemcontrol"
    public static let name = "系统控制"
    public static let icon = "bolt"
    public static let description = "macOS 系统级快捷指令聚合，支持锁定屏幕、睡眠、重启、关机、清空废纸篓与外观切换等操作。"
    public static let triggerWords = [
        "锁屏", "lock", "睡眠", "sleep", "重启", "restart", "关机", "shutdown", "推出", "深色", "dark"
    ]

    public var isEnabled = true

    private let log = QuickLog.plugin(SystemControlPlugin.id)

    /// 系统操作运行器
    private let runner = SystemActionRunner()

    /// 用户设置存储（用于别名）
    private let settingsStore: SettingsStore?

    /// 插件级触发词：全部操作关键词的并集，外加几个更短的中文口语说法
    ///
    /// 闸门与评分共用这套词；此前完全没有闸门，打一个 `l` 就会命中 `lock`。
    private static let triggers: [String] =
        SystemAction.allCases.flatMap(\.keywords) + ["推出", "深色"]

    /// 只打了触发词、没有剩余查询词时的基础相关度
    private static let defaultRelevance = 0.5

    public init(settingsStore: SettingsStore? = nil) {
        self.settingsStore = settingsStore
    }

    /// 每条系统操作都是一条命令。锁屏作为空查询时的那一条入口
    public static var commands: [CommandDescriptor] {
        SystemAction.allCases.map { action in
            CommandDescriptor(
                id: CommandID.systemAction(action.rawValue),
                pluginID: id,
                pluginName: name,
                title: action.title,
                subtitle: action.description,
                keywords: action.keywords,
                icon: action.icon,
                showsWhenQueryEmpty: action == .lockScreen,
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

    // MARK: - QuickPlugin 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [SearchableItem] = []

        for action in SystemAction.allCases {
            let alias = settingsStore?.alias(for: "system." + action.rawValue)
            var score: Double = 0

            if let alias, !alias.isEmpty {
                if alias.caseInsensitiveCompare(trimmed) == .orderedSame {
                    score = 1.0
                } else if alias.fuzzyMatch(trimmed) {
                    score = alias.fuzzyScore(trimmed)
                }
            }

            if score == 0 && trimmed.matchesAnyTrigger(Self.triggers) {
                let keyword = trimmed.removingTrigger(Self.triggers)
                if keyword.isEmpty {
                    score = Self.defaultRelevance
                } else if action.keywords.contains(where: { $0.fuzzyMatch(keyword) }) {
                    score = action.keywords.map { $0.fuzzyScore(keyword) }.max() ?? 0
                }
            } else if score == 0 && action.keywords.contains(where: { $0.fuzzyMatch(trimmed) }) {
                score = action.keywords.map { $0.fuzzyScore(trimmed) }.max() ?? 0
            }

            if score > 0 {
                let subtitle =
                    (alias != nil && !alias!.isEmpty)
                    ? "别名: \(alias!) · \(action.description)"
                    : action.description

                results.append(
                    SearchableItem(
                        id: "systemcontrol.\(action.rawValue)",
                        pluginID: Self.id,
                        title: action.title,
                        subtitle: subtitle,
                        icon: action.icon,
                        relevance: score,
                        action: { [weak self] in
                            self?.runner.execute(action)
                            EventBus.shared.post(HidePaletteEvent())
                        }
                    )
                )
            }
        }

        results.sort { $0.relevance > $1.relevance }
        return results
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
