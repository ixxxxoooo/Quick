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

        // 「在启动器中显示」关掉就整块不出现。默认开，所以没设置过时要当成开 ——
        // 用 bool(forKey:) 会把「没设置过」读成 false，那等于默认关闭。
        guard Self.isCommandVisible(key: PluginSettingKey.WindowManager.showInLauncher) else {
            return []
        }

        // 剥离触发词后再看布局关键词：`窗口` 只剩空串时应当列出全部布局，而不是一行都没有
        let keyword = query.removingTrigger(Self.triggerWords)

        return WindowLayout.allCases.compactMap { layout in
            // 每个布局命令有自己的开关（设置页里逐行那个复选框）
            guard Self.isCommandVisible(key: PluginSettingKey.WindowManager.commandVisible(layout.rawValue))
            else { return nil }

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

    /// 读一个默认开启的开关
    ///
    /// 设置页里的这些开关默认是开的，所以「键不存在」必须当成开。
    private static func isCommandVisible(key: String) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// 布局命令清单（设置页要用它列出逐条开关）
    ///
    /// 从 `WindowLayout` 派生而不是另抄一份：设置页按这些 id 写「是否显示」的开关，
    /// 两边一旦不一致，开关就会写进插件永远不读的键里。
    public var layoutCommands: [SettingsWindowLayoutCommand] {
        WindowLayout.allCases.map {
            SettingsWindowLayoutCommand(id: $0.rawValue, name: $0.title, icon: $0.icon)
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
