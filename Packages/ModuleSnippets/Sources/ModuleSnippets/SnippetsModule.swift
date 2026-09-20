// SnippetsModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 文本片段模块
///
/// 管理可复用的文本片段，支持关键词触发、变量替换和搜索。
/// 用户可以快速插入常用文本、邮件签名、代码模板等。
@MainActor
public final class SnippetsModule: QuickModule {

    public static let id = "snippets"
    public static let name = "文本片段"
    public static let icon = "curlybraces"
    public static let triggerWords = ["片段", "snippet", "模板", "template"]

    public var isEnabled = true

    private let log = QuickLog.module(SnippetsModule.id)

    /// 片段存储
    private let store = SnippetStore()

    /// 模板引擎
    private let templateEngine = TemplateEngine()

    /// 空查询列出全部片段时的基础相关度，避免整屏结果都是 0 分
    private static let defaultRelevance = 0.5

    public init() {}

    // MARK: - QuickModule 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        let matches = store.search(query)
        return matches.prefix(10).map { snippet in
            SearchableItem(
                id: "snippets.\(snippet.id)",
                moduleID: Self.id,
                title: snippet.title,
                subtitle: snippet.preview,
                icon: "curlybraces",
                relevance: query.isEmpty ? Self.defaultRelevance : snippet.title.fuzzyScore(query) * 0.8,
                shortcutHint: snippet.keyword.flatMap { ":\($0)" },
                action: { [weak self] in
                    guard let self else { return }
                    let expanded = self.templateEngine.expand(snippet.content)
                    EventBus.shared.post(CopyToClipboardEvent(text: expanded))
                    EventBus.shared.post(HidePaletteEvent())
                }
            )
        }
    }

    public func makeView() -> AnyView {
        AnyView(SnippetsView(store: store))
    }

    public func activate() {
        store.load()
        log.notice("模块已激活：加载 \(self.store.snippets.count, privacy: .public) 个片段")
    }

    public func deactivate() {
        store.save()
        log.notice("模块已停用，片段已落盘")
    }
}
