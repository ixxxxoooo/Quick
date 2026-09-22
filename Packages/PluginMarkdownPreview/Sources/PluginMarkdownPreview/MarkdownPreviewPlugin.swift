// MarkdownPreviewPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// Markdown 预览插件
///
/// 参考 Fasty markdown-preview 布局：
/// 工具栏（复制/清空）→ 左右双栏（编辑 + 预览）
@MainActor
public final class MarkdownPreviewPlugin: QuickPlugin {

    public static let id = "markdown-preview"
    public static let name = "Markdown 预览"
    public static let icon = "text.badge.checkmark"
    public static let description = "实时 Markdown 编辑与渲染预览，支持 GitHub 风格语法、代码高亮、表格排版与数学公式。"
    public static let triggerWords = ["Markdown 预览", "markdown", "md", "预览"]

    public var isEnabled = true

    private let log = QuickLog.plugin(MarkdownPreviewPlugin.id)

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }
        return [
            SearchableItem(
                id: "markdown-preview.open",
                pluginID: Self.id,
                title: Self.name,
                subtitle: "实时 Markdown 编辑与预览",
                icon: Self.icon,
                relevance: 0.7,
                action: { EventBus.shared.post(NavigateEvent(pluginID: Self.id)) }
            )
        ]
    }

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    ///
    /// 初始值就是面板默认展示的那段示例 Markdown。
    private let buffer = TextBuffer(
        """
        # 标题

        这是一段 **Markdown** 文本。

        - 列表项 1
        - 列表项 2

        `代码` 和 [链接](https://example.com)

        > 引用文本

        ```
        let x = 42
        ```
        """)

    public func makeView() -> AnyView {
        AnyView(MarkdownPreviewView(buffer: buffer))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
