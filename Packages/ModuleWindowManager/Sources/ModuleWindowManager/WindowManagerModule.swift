// WindowManagerModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 窗口管理模块
///
/// 通过 Accessibility API 控制窗口位置和大小。
/// 支持窗口平铺、半屏、全屏等布局操作。
@MainActor
public final class WindowManagerModule: QuickModule {

    public static let id = "windowmanager"
    public static let name = "窗口管理"
    public static let icon = "macwindow.on.rectangle"

    public var isEnabled = true

    private let log = QuickLog.module(WindowManagerModule.id)

    private let mover = WindowMover()

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        let triggers = ["窗口", "window", "平铺", "布局", "半屏", "全屏"]
        guard triggers.contains(where: { query.lowercased().contains($0) }) else { return [] }

        return WindowLayout.allCases.compactMap { layout in
            let score = layout.keywords.map { $0.fuzzyScore(query) }.max() ?? 0
            guard score > 0 else { return nil }
            return SearchableItem(
                id: "wm.\(layout.rawValue)",
                moduleID: Self.id,
                title: layout.title,
                subtitle: layout.description,
                icon: layout.icon,
                relevance: score * 0.7,
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
        log.notice("模块已激活")
    }

    public func deactivate() {
        log.notice("模块已停用")
    }
}
