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
    public static let icon = "text.quote"

    public var isEnabled = true

    /// 片段存储
    private let store = SnippetStore()

    /// 模板引擎
    private let templateEngine = TemplateEngine()

    public init() {}

    // MARK: - QuickModule 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        let matches = store.search(query)
        return matches.prefix(10).map { snippet in
            SearchableItem(
                id: "snippet.\(snippet.id)",
                moduleID: Self.id,
                title: snippet.title,
                subtitle: snippet.preview,
                icon: "text.quote",
                relevance: snippet.title.fuzzyScore(query) * 0.8,
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
    }

    public func deactivate() {
        store.save()
    }
}
