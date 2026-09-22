// WordCounterPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 字数统计工具
///
/// 参考 Fasty word-counter 布局：
/// 输入区 → 统计卡片行 → 语言特征
@MainActor
public final class WordCounterPlugin: QuickPlugin {

    public static let id = "word-counter"
    public static let name = "字数统计"
    public static let icon = "textformat.123"
    public static let description = "多维度文本字数统计，包括字符总数、无空格字符数、单词数、段落行数与预估阅读耗时。"
    public static let triggerWords = ["字数", "统计", "word count", "字符数", "行数"]

    public var isEnabled = true

    private let log = QuickLog.plugin(WordCounterPlugin.id)

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }
        return [
            SearchableItem(
                id: "word-counter.open",
                pluginID: Self.id,
                title: Self.name,
                subtitle: "统计字符数、单词数、行数、预估阅读时长",
                icon: Self.icon,
                relevance: 0.7,
                action: { EventBus.shared.post(NavigateEvent(pluginID: Self.id)) }
            )
        ]
    }

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(WordCounterView(buffer: buffer))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
