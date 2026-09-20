// WindowManagerPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 窗口管理插件
///
/// 通过 Accessibility API 控制窗口位置和大小。
/// 支持窗口平铺、半屏、全屏等布局操作。
@MainActor
public final class WindowManagerPlugin: QuickPlugin {

    public static let id = "windowmanager"
    public static let name = "窗口管理"
    public static let icon = "macwindow"
    public static let triggerWords = ["窗口", "window", "平铺", "布局", "半屏", "全屏"]

    public var isEnabled = true

    private let log = QuickLog.plugin(WindowManagerPlugin.id)

    private let mover = WindowMover()

    /// 只打了触发词、没有剩余查询词时的基础相关度
    private static let defaultRelevance = 0.5

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }

        // 剥离触发词后再看布局关键词：`窗口` 只剩空串时应当列出全部布局，而不是一行都没有
        let keyword = query.removingTrigger(Self.triggerWords)

        return WindowLayout.allCases.compactMap { layout in
            let score = keyword.isEmpty ? 0 : layout.keywords.map { $0.fuzzyScore(keyword) }.max() ?? 0
            guard keyword.isEmpty || score > 0 else { return nil }
            return SearchableItem(
                id: "windowmanager.\(layout.rawValue)",
                pluginID: Self.id,
                title: layout.title,
                subtitle: layout.description,
                icon: layout.icon,
                relevance: keyword.isEmpty ? Self.defaultRelevance : score * 0.7,
                action: { [weak self] in
                    self?.mover.apply(layout)
                    EventBus.shared.post(HidePaletteEvent())
                }
            )
        }
    }

    public func makeView() -> AnyView {
        AnyView(WindowManagerView(mover: mover))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
