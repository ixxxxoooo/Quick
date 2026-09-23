// PaletteSearchEngine.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Foundation
import os
import QuickCore

/// 主面板聚合搜索：静态命令索引 + 插件动态搜索
///
/// 从 `PaletteCoordinator` 抽出的纯搜索逻辑，协调器只负责注入依赖与面板生命周期。
@MainActor
public enum PaletteSearchEngine {

    /// 单次搜索的结果上限
    ///
    /// 没有上限时，一个失控的插件会把几千条塞进 SwiftUI 列表、还要在主线程排序。
    public static let resultLimit = 60

    /// 单个插件的动态搜索超时
    ///
    /// 插件的 `dynamicSearch` 跑在主 actor 上，一个慢查询会把整批结果卡住；
    /// 超时之后放弃这个插件，而不是让整块面板陪它等。
    public static let pluginTimeout = Duration.seconds(2)

    /// 聚合搜索：静态命令索引 + 声明了动态结果的插件
    ///
    /// 静态打分不碰插件对象，可以离开主线程。动态插件只有 `accepts` 为真才调用，
    /// 并且超时会取消等待。
    ///
    /// - Parameters:
    ///   - query: 搜索关键词
    ///   - staticCommands: 启动时快照的静态命令索引
    ///   - plugins: 已注册插件实例
    ///   - isSearchSourceEnabled: 设置里是否允许该插件参与主搜索
    ///   - recentItemIDs: 空查询时用于首屏提权的最近使用 id（通常最多 12 条）
    ///   - invokeCommand: 命中静态命令时的执行入口
    ///   - log: 面板分类日志
    /// - Returns: 去重、排序、限流之后的结果
    public static func search(
        query: String,
        staticCommands: [IndexedCommand],
        plugins: [any QuickPlugin],
        isSearchSourceEnabled: (String) -> Bool,
        recentItemIDs: [String],
        invokeCommand: @escaping @MainActor (String) -> Void,
        log: Logger
    ) async -> [SearchableItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let signpost = QuickLog.signposter(QuickLog.Category.palette)
        let interval = signpost.beginInterval("palette.search")
        let started = Date()
        let commands = staticCommands

        let staticHits = await Task.detached {
            CommandIndex.matching(commands, query: trimmed)
        }.value
        if Task.isCancelled {
            signpost.endInterval("palette.search", interval)
            return []
        }

        let staticItems = staticHits.map { hit in
            let descriptor = hit.command.descriptor
            return SearchableItem(
                id: descriptor.id,
                pluginID: descriptor.pluginID,
                pluginName: descriptor.pluginName,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                icon: descriptor.icon,
                relevance: hit.relevance,
                action: {
                    invokeCommand(descriptor.id)
                }
            )
        }

        let dynamicPlugins = plugins.filter { plugin in
            let pluginID = type(of: plugin).id
            return plugin.isEnabled && isSearchSourceEnabled(pluginID) && plugin.accepts(query: trimmed)
        }

        let dynamicItems = await withTaskGroup(of: [SearchableItem].self) { group in
            for plugin in dynamicPlugins {
                let pluginName = type(of: plugin).name
                let pluginID = type(of: plugin).id
                group.addTask {
                    let items = await searchDynamic(
                        plugin: plugin, pluginID: pluginID, query: trimmed, log: log)
                    return items.map { $0.pluginName == nil ? $0.withPluginName(pluginName) : $0 }
                }
            }
            var results: [SearchableItem] = []
            for await items in group {
                results.append(contentsOf: items)
            }
            return results
        }

        if Task.isCancelled {
            signpost.endInterval("palette.search", interval)
            return []
        }

        let collected = staticItems + dynamicItems

        // 去重：`SearchableItem` 的 `Hashable` 只看 id。重复 id 会让 `ForEach` 进入未定义行为。
        var seen = Set<String>()
        let deduped = collected.filter { seen.insert($0.id).inserted }

        var sorted = deduped.sorted {
            $0.relevance == $1.relevance ? $0.id < $1.id : $0.relevance > $1.relevance
        }

        if trimmed.isEmpty {
            sorted = promotingRecents(sorted, recents: recentItemIDs)
        }

        let limited = Array(sorted.prefix(resultLimit))

        signpost.endInterval("palette.search", interval)
        let elapsedMS = Date().timeIntervalSince(started) * 1000
        if elapsedMS > 50 {
            log.warning(
                """
                聚合搜索超过 50ms：动态插件 \(dynamicPlugins.count, privacy: .public) 个，\
                返回 \(limited.count, privacy: .public) 条，\
                耗时 \(elapsedMS, format: .fixed(precision: 1)) ms
                """
            )
        } else {
            log.debug(
                """
                聚合搜索完成：静态 \(staticItems.count, privacy: .public) 条，\
                动态插件 \(dynamicPlugins.count, privacy: .public) 个，\
                返回 \(limited.count, privacy: .public) 条，\
                耗时 \(elapsedMS, format: .fixed(precision: 1)) ms
                """
            )
        }

        return limited
    }

    /// 查询单个动态插件，超时即取消等待
    private static func searchDynamic(
        plugin: any QuickPlugin,
        pluginID: String,
        query: String,
        log: Logger
    ) async -> [SearchableItem] {
        let started = Date()
        return await withTaskGroup(of: [SearchableItem]?.self) { group in
            group.addTask {
                await plugin.dynamicSearch(query: query)
            }
            group.addTask {
                try? await Task.sleep(for: pluginTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            if first == nil {
                let elapsedMS = Date().timeIntervalSince(started) * 1000
                log.warning(
                    """
                    插件 \(pluginID, privacy: .public) 搜索超时，已取消等待，\
                    耗时 \(elapsedMS, format: .fixed(precision: 1)) ms
                    """
                )
                return []
            }
            return first ?? []
        }
    }

    /// 把最近使用过的条目提到前面，其余保持原顺序
    ///
    /// 抽成独立函数是为了能单独测：这里只做重排，不碰数据库、不碰插件。
    public static func promotingRecents(
        _ items: [SearchableItem],
        recents: [String]
    ) -> [SearchableItem] {
        guard !recents.isEmpty else { return items }

        let rank = Dictionary(uniqueKeysWithValues: recents.enumerated().map { ($1, $0) })
        let (recent, rest) = items.reduce(into: ([SearchableItem](), [SearchableItem]())) {
            if rank[$1.id] != nil { $0.0.append($1) } else { $0.1.append($1) }
        }
        // 按「最近」的顺序排，而不是按它们原来的相关度 —— 这里要的就是时间顺序
        return recent.sorted { (rank[$0.id] ?? 0) < (rank[$1.id] ?? 0) } + rest
    }
}
