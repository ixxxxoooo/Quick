// ClipboardModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 剪贴板历史模块
///
/// 监听系统剪贴板变化，自动记录历史条目。
/// 支持搜索、分类（文本/图片/文件）、收藏和快速粘贴。
@MainActor
public final class ClipboardModule: QuickModule {

    public static let id = "clipboard"
    public static let name = "剪贴板历史"
    public static let icon = "doc.on.clipboard"
    public static let triggerWords = ["剪贴板", "clipboard", "粘贴", "复制", "历史", "cb"]

    public var isEnabled = true

    private let log = QuickLog.module(ClipboardModule.id)

    /// 剪贴板监听器
    private let monitor = ClipboardMonitor()

    /// 剪贴板条目存储
    private let store = ClipboardStore()

    public init() {}

    // MARK: - QuickModule 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        // 仅当搜索词与剪贴板相关时才返回入口
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }

        // 剥离触发词后的词才是真正的筛选条件；为空表示列出最近几条
        let keyword = query.removingTrigger(Self.triggerWords)
        let matches = keyword.isEmpty ? store.entries : store.search(keyword)

        var results: [SearchableItem] = []

        // 第一项：打开剪贴板管理器面板（导航到模块模式）
        results.append(
            SearchableItem(
                id: "clipboard.open-panel",
                moduleID: Self.id,
                title: "打开剪贴板管理器",
                subtitle: "查看全部 \(store.entries.count) 条剪贴板历史",
                icon: Self.icon,
                relevance: 0.9,
                action: {
                    EventBus.shared.post(
                        NavigateEvent(moduleID: ClipboardModule.id))
                }
            ))

        // 最近的几条剪贴板记录，点击直接复制
        results += matches.prefix(5).map { entry in
            SearchableItem(
                id: "clipboard.\(entry.id)",
                moduleID: Self.id,
                title: entry.preview,
                subtitle: entry.timestamp.formatted(date: .abbreviated, time: .shortened),
                icon: entry.type.icon,
                relevance: 0.5,
                action: {
                    EventBus.shared.post(CopyToClipboardEvent(text: entry.text))
                    EventBus.shared.post(HidePaletteEvent())
                }
            )
        }

        return results
    }

    public func makeView() -> AnyView {
        AnyView(ClipboardListView(store: store))
    }

    public func makeSettingsView() -> AnyView? {
        // 配置项由 FeatureSettingsPane 的 ClipboardFeatureSection 统一管理
        nil
    }

    public func activate() {
        store.load()
        monitor.onNewContent = { [weak self] entry in
            self?.store.add(entry)
        }
        monitor.start()
        log.notice(
            """
            模块已激活：加载 \(self.store.entries.count, privacy: .public) 条历史，\
            剪贴板监听已启动
            """)
    }

    public func deactivate() {
        monitor.stop()
        store.save()
        log.notice("模块已停用，剪贴板监听已停止，历史已落盘")
    }
}
