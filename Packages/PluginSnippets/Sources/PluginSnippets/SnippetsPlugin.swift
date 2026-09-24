// SnippetsPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 文本片段插件
///
/// 管理可复用的文本片段，支持关键词触发、变量替换和搜索。
/// 用户可以快速插入常用文本、邮件签名、代码模板等。
@MainActor
public final class SnippetsPlugin: QuickPlugin, PluginViewProviding {

    public static let id = "snippets"
    public static let name = "文本片段"
    public static let icon = "text.quote"
    public static let description = "常用代码片段与模板快捷管理器，支持预定义占位符、动态参数求值与全局快速粘贴插入。"
    public static let triggerWords = ["片段", "snippet", "模板", "template", "代码片段"]

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "snippets.new", pluginID: id, pluginName: name, title: "新建片段",
                subtitle: "创建一条文本片段", keywords: ["新建片段", "片段新建"],
                icon: "text.badge.plus")
        ]
    }

    public var isEnabled = true

    private let log = QuickLog.plugin(SnippetsPlugin.id)

    /// 片段存储
    private let store: SnippetStore

    /// 模板引擎
    private let templateEngine = TemplateEngine()

    /// 空查询列出全部片段时的基础相关度，避免整屏结果都是 0 分
    /// 空查询时片段的默认相关度
    private nonisolated static let defaultRelevance = 0.5

    /// - Parameter storage: 由 AppCore 注入的存储句柄
    public init(storage: PluginStorage) {
        self.store = SnippetStore(storage: storage)
    }

    // MARK: - 存储 schema

    /// 片段表
    ///
    /// 表结构归插件所有：宿主只负责把它跑一遍，不读这张表。
    public static var storageMigrations: [SQLiteMigration] {
        [
            SQLiteMigration(
                id: "snippets.items",
                statements: [
                    """
                    CREATE TABLE IF NOT EXISTS snippets (
                        id TEXT PRIMARY KEY,
                        title TEXT NOT NULL DEFAULT '',
                        content TEXT NOT NULL DEFAULT '',
                        keyword TEXT,
                        category TEXT,
                        created_at REAL NOT NULL,
                        updated_at REAL NOT NULL
                    )
                    """,
                    "CREATE INDEX IF NOT EXISTS idx_snippets_created ON snippets(created_at DESC)"
                ])
        ]
    }

    // MARK: - QuickPlugin 协议

    public func accepts(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        if trimmed.matchesAnyTrigger(Self.triggerWords) { return true }
        return store.acceptsQuery(trimmed)
    }

    public nonisolated func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }

        // 触发提示是结果项的一部分，所以在构造结果项这一刻现读：
        // 设置页可以在面板开着的时候改这个开关，init 里读一次就再也跟不上
        let showsHint = PluginDefaults.isEnabled(
            PluginSettingKey.Snippets.showSnippetHint, default: true)

        let matches = store.search(query)
        return matches.prefix(10).map { snippet in
            SearchableItem(
                id: "snippets.\(snippet.id)",
                pluginID: Self.id,
                title: snippet.title,
                subtitle: snippet.preview,
                icon: "curlybraces",
                relevance: query.isEmpty ? Self.defaultRelevance : snippet.title.fuzzyScore(query) * 0.8,
                shortcutHint: showsHint ? snippet.keyword.flatMap { ":\($0)" } : nil,
                action: { [weak self] in
                    guard let self else { return }
                    // 再读一次「自动展开」：从列出片段到按下回车之间，设置页可能已经改过它。
                    // 关掉开关的用户要的是原文，模板变量替换属于「展开」承诺的一部分，一并省掉。
                    let text =
                        PluginDefaults.isEnabled(PluginSettingKey.Snippets.autoExpand, default: true)
                        ? self.templateEngine.expand(snippet.content)
                        : snippet.content
                    EventBus.shared.post(CopyToClipboardEvent(text: text))
                    EventBus.shared.post(HidePaletteEvent())
                }
            )
        }
    }

    public func makeView() -> AnyView {
        AnyView(SnippetsView(store: store))
    }

    public func activate() {
        // 加载已在 init 里完成，这里只汇报
        log.notice("插件已激活：加载 \(self.store.snippets.count, privacy: .public) 个片段")
    }

    public func deactivate() {
        store.save()
        log.notice("插件已停用，片段已落盘")
    }
}
