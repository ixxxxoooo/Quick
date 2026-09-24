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
public final class FileSearchPlugin: QuickPlugin, PluginViewProviding {

    public static let id = "filesearch"
    public static let name = "文件搜索"
    public static let icon = "folder.fill.badge.magnifyingglass"
    public static let description = "基于 macOS Spotlight 原生索引的高性能文件搜索，支持全盘文件名匹配与内容深度检索。"
    public static let triggerWords = ["f", "file", "文件"]

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "filesearch.content", pluginID: id, pluginName: name, title: "搜索文件内容",
                subtitle: "在文件内容里搜索关键词", keywords: ["文件内容", "内容搜索"],
                icon: "doc.text.magnifyingglass")
        ]
    }

    public var isEnabled = true

    private let log = QuickLog.plugin(FileSearchPlugin.id)

    /// Spotlight 搜索引擎
    ///
    /// internal 而不是 private：结果上限与两个开关都由会话从设置读出来，接线测试要能从这里
    /// 拿到它验证设置确实传到了查询与后处理。
    let searchSession = FileSearchSession()

    public init() {}

    // MARK: - QuickPlugin 协议

    public func accepts(query: String) -> Bool {
        FileSearchQuery.keyword(in: query) != nil
    }

    public nonisolated func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }
        // 闸门：必须以 "f " / "file " / "文件 " 开头且后面还有关键词，否则返回空、
        // 不去打扰 Spotlight。`accepts` 已经挡了一层，这里再挡一次是因为
        // `dynamicSearch` 也能被直接调用（测试、未来的其它入口），而触发词解析是纯逻辑
        // （见 FileSearchQuery），重复判断的代价可以忽略。
        guard let keyword = FileSearchQuery.keyword(in: query) else { return [] }

        // 会话已经在查询前读过一次设置：谓词按「搜索文件内容」开关构造，
        // 结果按「忽略隐藏文件」过滤并按「最大结果数」截断。
        // NSMetadataQuery 必须跑在主 actor 上（要 runloop 派发通知），
        // 所以这里显式跳回去 —— 这一次跳跃是有意的，不是遗漏。
        let files = await searchSession.search(query: keyword)
        return Self.items(for: files)
    }

    /// 把搜索结果映射成面板条目
    ///
    /// `nonisolated static`：纯映射，不碰实例状态，这样从无隔离的搜索路径调用
    /// 不必再回主 actor。测试也靠它在不跑 Spotlight 的前提下验证没有二次截断 ——
    /// 以前这里写死 `prefix(10)`，设置页里的 20/50/100/200 全都被压成 10 条。
    nonisolated static func items(for files: [FileSearchSession.FileResult]) -> [SearchableItem] {
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

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(FileSearchView(session: searchSession, buffer: buffer))
    }

    public func activate() {
        log.notice("插件已激活，文件搜索使用 Spotlight 索引")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
