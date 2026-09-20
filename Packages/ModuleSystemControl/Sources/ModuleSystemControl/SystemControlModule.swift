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

    /// 系统操作运行器
    private let runner = SystemActionRunner()

    public init() {}

    // MARK: - QuickModule 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        let actions = SystemAction.allCases
        guard !query.isEmpty else { return [] }

        return actions
            .filter { action in
                action.keywords.contains { $0.fuzzyMatch(query) }
            }
            .map { action in
                SearchableItem(
                    id: "syscontrol.\(action.rawValue)",
                    moduleID: Self.id,
                    title: action.title,
                    subtitle: action.description,
                    icon: action.icon,
                    relevance: action.keywords.map { $0.fuzzyScore(query) }.max() ?? 0,
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
}
