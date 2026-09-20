// SystemControlModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 系统控制模块
///
/// 提供常用系统操作的快捷入口：锁屏、睡眠、重启、
/// 关机、清空废纸篓、弹出磁盘、屏幕保护程序等。
@MainActor
public final class SystemControlModule: QuickModule {

    public static let id = "systemcontrol"
    public static let name = "系统控制"
    public static let icon = "gearshape"

    public var isEnabled = true

    private let log = QuickLog.module(SystemControlModule.id)

    /// 系统操作运行器
    private let runner = SystemActionRunner()

    /// 模块级触发词：全部操作关键词的并集，外加几个更短的中文口语说法
    ///
    /// 闸门与评分共用这套词；此前完全没有闸门，打一个 `l` 就会命中 `lock`。
    private static let triggers: [String] =
        SystemAction.allCases.flatMap(\.keywords) + ["推出", "深色"]

    /// 只打了触发词、没有剩余查询词时的基础相关度
    private static let defaultRelevance = 0.5

    public init() {}

    // MARK: - QuickModule 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggers) else { return [] }

        // 剥离触发词后的词才是真正的筛选条件；为空表示列出全部操作
        let keyword = query.removingTrigger(Self.triggers)

        return
            SystemAction.allCases
            .filter { action in
                keyword.isEmpty || action.keywords.contains { $0.fuzzyMatch(keyword) }
            }
            .map { action in
                SearchableItem(
                    id: "systemcontrol.\(action.rawValue)",
                    moduleID: Self.id,
                    title: action.title,
                    subtitle: action.description,
                    icon: action.icon,
                    relevance: keyword.isEmpty
                        ? Self.defaultRelevance
                        : action.keywords.map { $0.fuzzyScore(keyword) }.max() ?? 0,
                    action: { [weak self] in
                        self?.runner.execute(action)
                        EventBus.shared.post(HidePaletteEvent())
                    }
                )
            }
    }

    public func makeView() -> AnyView {
        AnyView(SystemControlView(runner: runner))
    }

    public func activate() {
        log.notice("模块已激活，可用系统操作 \(SystemAction.allCases.count, privacy: .public) 项")
    }

    public func deactivate() {
        log.notice("模块已停用")
    }
}
