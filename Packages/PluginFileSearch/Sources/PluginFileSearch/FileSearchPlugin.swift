// FileSearchPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 文件搜索插件
///
/// 基于 NSMetadataQuery（Spotlight）的文件搜索。
/// 支持按名称、内容搜索文件，并可快速打开或在 Finder 中显示。
@MainActor
public final class FileSearchPlugin: QuickPlugin {

    public static let id = "filesearch"
    public static let name = "文件搜索"
    public static let icon = "doc.text.magnifyingglass"
    public static let triggerWords = ["f", "file", "文件"]

    public var isEnabled = true

    private let log = QuickLog.plugin(FileSearchPlugin.id)

    /// Spotlight 搜索引擎
    private let searchSession = FileSearchSession()

    public init() {}

    // MARK: - QuickPlugin 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        // 仅当搜索词以 "f " 或 "file " 开头时触发文件搜索
        let triggers = ["f ", "file ", "文件 "]
        guard let trigger = triggers.first(where: { query.lowercased().hasPrefix($0) }) else {
            return []
        }
        let keyword = String(query.dropFirst(trigger.count))
        guard !keyword.isEmpty else { return [] }

        let files = await searchSession.search(query: keyword)
        return files.prefix(10).map { file in
            SearchableItem(
                id: "filesearch.\(file.path)",
                pluginID: Self.id,
                title: file.name,
                subtitle: file.path,
                icon: file.icon,
                relevance: 0.6,
                action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
                    EventBus.shared.post(HidePaletteEvent())
                }
            )
        }
    }

    public func makeView() -> AnyView {
        AnyView(FileSearchView(session: searchSession))
    }

    public func activate() {
        log.notice("插件已激活，文件搜索使用 Spotlight 索引")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
