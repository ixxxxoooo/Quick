// PaletteSearchEngine.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import os
import QuickCore

/// 一次聚合搜索的结果
///
/// 把「超时」与「没搜到」分开，是这一版搜索最主要的修复：以前超时静默返回空数组，
/// 用户看到的是「没找到」，而实际原因是「没搜完」。
public struct PaletteSearchOutcome: Sendable {

    /// 去重、排序、限流之后的条目
    public let items: [SearchableItem]

    /// 超时被放弃的插件 id；非空表示这次结果不完整
    public let timedOutPluginIDs: [String]

    /// 空结果
    public static let empty = PaletteSearchOutcome(items: [], timedOutPluginIDs: [])
}

/// 单个插件的搜索产出
private struct PluginSearchResult: Sendable {

    let pluginID: String

    /// `nil` 表示超时；空数组表示「查了但没有结果」
    let items: [SearchableItem]?

    let didTimeOut: Bool
}

/// 一轮动态搜索的汇总
private struct DynamicSearchBatch: Sendable {

    let items: [SearchableItem]

    let timedOutPluginIDs: [String]
}

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
    /// 插件的 `dynamicSearch` 是 `nonisolated`，正常情况下不该阻塞主 actor；
    /// 但网络、磁盘这类真实 IO 仍可能长时间不返回。超时之后放弃这个插件，
    /// 而不是让整块面板陪它等 —— 超时的插件 id 会随结果一起返回给调用方。
    public static let pluginTimeout = Duration.seconds(2)

    /// 聚合搜索：静态命令索引 + 声明了动态结果的插件
    ///
    /// 静态打分不碰插件对象，可以离开主线程。动态插件只有 `accepts` 为真才调用。
    ///
    /// - Parameters:
    ///   - query: 搜索关键词
    ///   - staticCommands: 启动时快照的静态命令索引
    ///   - plugins: 已注册插件实例
    ///   - isSearchSourceEnabled: 设置里是否允许该插件参与主搜索
    ///   - recentItemIDs: 空查询时用于首屏提权的最近使用 id（通常最多 12 条）
    ///   - invokeCommand: 命中静态命令时的执行入口
    ///   - log: 面板分类日志
    ///   - pluginTimeout: 单个插件的超时；测试会传一个很短的值
    /// - Returns: 去重、排序、限流之后的结果，附带超时的插件 id
    public static func search(
        query: String,
        staticCommands: [IndexedCommand],
        plugins: [any QuickPlugin],
        isSearchSourceEnabled: (String) -> Bool,
        recentItemIDs: [String],
        invokeCommand: @escaping @MainActor @Sendable (String) -> Void,
        log: Logger,
        pluginTimeout: Duration = PaletteSearchEngine.pluginTimeout
    ) async -> PaletteSearchOutcome {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let signpost = QuickLog.signposter(QuickLog.Category.palette)
        let interval = signpost.beginInterval("palette.search")
        let started = Date()

        // 空查询只做「每插件取一条入口」——83 条命令的遍历加去重，实测 0.05 ms 量级。
        // 为它付一次 `Task.detached` 的线程跳转是负收益：主线程忙（首次渲染）时那次
        // 跳转的等待能到 100 ms 级，而它换来的并行节省不到 0.1 ms。
        // 这里曾经无条件 detach，日志里因此出现过「聚合搜索超过 50ms」的假警报。
        let staticHits: [CommandHit]
        if trimmed.isEmpty {
            staticHits = CommandIndex.matching(staticCommands, query: trimmed)
        } else {
            let commands = staticCommands
            staticHits = await Task.detached {
                CommandIndex.matching(commands, query: trimmed)
            }.value
        }
        if Task.isCancelled {
            signpost.endInterval("palette.search", interval)
            return .empty
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

        // `accepts` 现在是 nonisolated，闸门判定不再占用主 actor
        let dynamicPlugins = plugins.filter { plugin in
            let pluginID = type(of: plugin).id
            return plugin.isEnabled && isSearchSourceEnabled(pluginID) && plugin.accepts(query: trimmed)
        }

        let dynamicItems = await withTaskGroup(of: PluginSearchResult.self) { group in
            for plugin in dynamicPlugins {
                let pluginName = type(of: plugin).name
                let pluginID = type(of: plugin).id
                group.addTask {
                    let outcome = await searchDynamic(
                        plugin: plugin, pluginID: pluginID, query: trimmed, log: log,
                        timeout: pluginTimeout)
                    guard let items = outcome.items else {
                        return PluginSearchResult(pluginID: pluginID, items: nil, didTimeOut: true)
                    }
                    // 插件没自己填来源名时补上，结果行右侧的插件徽章靠它
                    let named = items.map { item in
                        item.pluginName == nil ? item.withPluginName(pluginName) : item
                    }
                    return PluginSearchResult(pluginID: pluginID, items: named, didTimeOut: false)
                }
            }
            var results: [SearchableItem] = []
            var timedOut: [String] = []
            for await outcome in group {
                if let items = outcome.items {
                    results.append(contentsOf: items)
                }
                if outcome.didTimeOut { timedOut.append(outcome.pluginID) }
            }
            return DynamicSearchBatch(items: results, timedOutPluginIDs: timedOut)
        }

        if Task.isCancelled {
            signpost.endInterval("palette.search", interval)
            return .empty
        }

        let collected = staticItems + dynamicItems.items

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
        let timedOutIDs = dynamicItems.timedOutPluginIDs

        signpost.endInterval("palette.search", interval)
        let elapsedMS = Date().timeIntervalSince(started) * 1000
        if elapsedMS > 50 {
            log.warning(
                """
                聚合搜索超过 50ms：动态插件 \(dynamicPlugins.count, privacy: .public) 个，\
                返回 \(limited.count, privacy: .public) 条，\
                超时 \(timedOutIDs.count, privacy: .public) 个，\
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

        return PaletteSearchOutcome(items: limited, timedOutPluginIDs: timedOutIDs)
    }

    /// 查询单个动态插件，超时即取消它的工作
    ///
    /// **取消是合作式的，不是强制的。** `dynamicSearch` 是 `nonisolated`，`cancelAll()`
    /// 只把取消标志送到插件内部，插件要在 `await` 点或循环里看 `Task.isCancelled`
    /// 才会真的收尾。这不改变「超时后不等它」这一行为：整块面板仍然按超时返回。
    ///
    /// - Returns: 插件的条目；超时返回 nil（与「查了但没结果」区分开）
    private static func searchDynamic(
        plugin: any QuickPlugin,
        pluginID: String,
        query: String,
        log: Logger,
        timeout: Duration
    ) async -> PluginSearchResult {
        let started = Date()
        let items = await withTaskGroup(of: [SearchableItem]?.self) { group in
            group.addTask {
                await plugin.dynamicSearch(query: query)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        guard let items else {
            let elapsedMS = Date().timeIntervalSince(started) * 1000
            // 不静默：超时是「没搜完」，不是「没找到」，用户与排查者都要能分辨
            log.warning(
                """
                插件 \(pluginID, privacy: .public) 搜索超时，已取消其工作，\
                耗时 \(elapsedMS, format: .fixed(precision: 1)) ms
                """
            )
            return PluginSearchResult(pluginID: pluginID, items: nil, didTimeOut: true)
        }
        return PluginSearchResult(pluginID: pluginID, items: items, didTimeOut: false)
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
