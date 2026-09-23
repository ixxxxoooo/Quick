// KillProcessPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 结束进程插件
///
/// 按 CPU / 内存排序列出进程，支持标题栏搜索筛选与结束 / 强制结束。
/// 布局参考 Raycast Kill Process；搜索框走 `supportsPanelSearch` 落在面板标题栏。
@MainActor
public final class KillProcessPlugin: QuickPlugin {

    public static let id = "killprocess"
    public static let name = "结束进程"
    public static let icon = "xmark.octagon.fill"
    public static let description = "按 CPU 或内存排序查看运行中的进程，支持筛选并结束或强制结束。"
    public static let triggerWords = [
        "结束进程", "杀进程", "进程", "kill", "killprocess", "process", "终止进程", "强制结束"
    ]

    public static var supportsPanelSearch: Bool { true }

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "killprocess.kill", pluginID: id, pluginName: name, title: "结束进程",
                subtitle: "按名称查找并结束进程", keywords: ["结束进程", "杀进程"],
                icon: "xmark.app")
        ]
    }

    public var isEnabled = true

    private let log = QuickLog.plugin(KillProcessPlugin.id)

    /// 进程列表服务（与视图共享同一实例）
    let service = KillProcessService()

    /// 面板显隐订阅；不保存会被 ARC 立刻取消
    private var visibilitySubscription: EventSubscription?

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }
        return [
            SearchableItem(
                id: "killprocess.overview",
                pluginID: Self.id,
                title: "结束进程",
                subtitle: "按 CPU / 内存排序并终止进程",
                icon: "xmark.circle",
                relevance: 0.6,
                action: {
                    EventBus.shared.post(NavigateEvent(pluginID: Self.id))
                }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(KillProcessView(service: service))
    }

    public func activate() {
        // 面板隐藏（orderOut）不会触发视图的 onDisappear，采样必须由面板显隐事件叫停
        visibilitySubscription = EventBus.shared.on(PaletteVisibilityChangedEvent.self) {
            [weak self] event in
            self?.service.notePanelVisibility(event.isVisible)
        }
        log.notice("插件已激活")
    }

    public func deactivate() {
        visibilitySubscription?.cancel()
        visibilitySubscription = nil
        service.noteViewDisappeared()
        log.notice("插件已停用")
    }
}
