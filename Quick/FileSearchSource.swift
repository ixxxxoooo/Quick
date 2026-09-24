// FileSearchSource.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation
import QuickCore
import QuickPlatform
import QuickUI

/// 文件搜索作为宿主的一个搜索来源
///
/// **它不是插件**：文件搜索由 `QuickPlatform` 提供能力，装配在这里，结果直接进主搜索
/// 列表。因此它不出现在插件列表、不能被单独禁用、也没有自己的面板 —— 面板、设置页、
/// 触发词守卫都不需要，输入 `f ` 前缀就在主搜索里出文件。
///
/// 触发词解析（`FileSearchQuery`）与结果过滤（`FileSearchFiltering`）都是
/// `QuickPlatform` 里的纯逻辑，这里只负责把两侧接上并把结果映射成面板条目。
@MainActor
final class FileSearchSource: PaletteHostSearchSource {

    nonisolated let sourceID = "filesearch"
    nonisolated let displayName = "文件搜索"

    private let service: FileSearchService
    private let log = QuickLog.app

    init(service: FileSearchService = FileSearchService()) {
        self.service = service
    }

    /// 闸门：必须以 `f ` / `file ` / `文件 ` 开头且后面还有关键词
    ///
    /// 不这样做的话每一次按键都会去打扰 Spotlight —— 那个查询要跑整机索引。
    func accepts(query: String) -> Bool {
        FileSearchQuery.keyword(in: query) != nil
    }

    func search(query: String) async -> [SearchableItem] {
        guard let keyword = FileSearchQuery.keyword(in: query) else { return [] }
        let files = await service.search(keyword: keyword)
        guard !Task.isCancelled else { return [] }
        log.debug("文件搜索返回 \(files.count, privacy: .public) 条")
        return Self.items(for: files)
    }

    /// 把搜索结果映射成面板条目
    ///
    /// 不做二次截断：条数由设置里的上限决定（`FileSearchService` 已经按它截过）。
    static func items(for files: [FileSearchService.FileResult]) -> [SearchableItem] {
        files.map { file in
            SearchableItem(
                id: "filesearch.\(file.path)",
                pluginID: "filesearch",
                pluginName: "文件搜索",
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
}
