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
    ///
    /// internal 而不是 private：结果上限与两个开关都由会话从设置读出来，接线测试要能从这里
    /// 拿到它验证设置确实传到了查询与后处理。
    let searchSession = FileSearchSession()

    public init() {}

    // MARK: - QuickPlugin 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        // 触发词解析是纯逻辑，见 FileSearchQuery：必须以 "f " / "file " / "文件 " 开头，
        // 且后面还要有关键词，否则这里就返回空、不去打扰 Spotlight
        guard let keyword = FileSearchQuery.keyword(in: query) else { return [] }

        // 会话已经在查询前读过一次设置：谓词按「搜索文件内容」开关构造，
        // 结果按「忽略隐藏文件」过滤并按「最大结果数」截断
        let files = await searchSession.search(query: keyword)
        return items(for: files)
    }

    /// 把搜索结果映射成面板条目
    ///
    /// internal 而不是 private：接线测试要能在不跑 Spotlight 的前提下验证这里没有二次截断。
    /// 以前这里写死 `prefix(10)`，设置页里的 20/50/100/200 全都被压成 10 条。
    func items(for files: [FileSearchSession.FileResult]) -> [SearchableItem] {
        files.map { file in
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
