// CommandIndex.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一条已经预处理过匹配形态的命令
///
/// 拼音和大小写折叠在建索引时做一次。每次按键只打分，不再碰插件对象。
public struct IndexedCommand: Sendable, Identifiable {

    /// 原始描述符
    public let descriptor: CommandDescriptor

    /// 标题匹配形态（权重 1.0）
    public let titleText: MatchText

    /// 触发关键字匹配形态（权重 0.9）
    public let keywordTexts: [MatchText]

    /// 插件分类名匹配形态（权重 0.8）
    public let pluginNameText: MatchText

    /// 副标题小写文本（仅用于精确连续子串包含，不转写拼音、不走散落子序列）
    public let subtitleLower: String?

    public var id: String { descriptor.id }

    /// 用描述符建索引
    public init(_ descriptor: CommandDescriptor) {
        self.descriptor = descriptor
        self.titleText = MatchText(descriptor.title)
        self.pluginNameText = MatchText(descriptor.pluginName)

        var seen = Set<String>()
        var keywords: [MatchText] = []
        for s in descriptor.keywords {
            let key = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty && seen.insert(key).inserted {
                keywords.append(MatchText(s))
            }
        }
        self.keywordTexts = keywords

        if let sub = descriptor.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !sub.isEmpty {
            self.subtitleLower = sub
        } else {
            self.subtitleLower = nil
        }
    }
}

/// 一次静态命令命中
public struct CommandHit: Sendable {

    /// 命中的命令
    public let command: IndexedCommand

    /// 相关度，0 到 1
    public let relevance: Double
}

/// 静态命令的内存索引
///
/// 全部是纯函数，调用方可以把快照丢到后台线程打分。
public enum CommandIndex {

    /// 空查询时插件入口的相关度
    ///
    /// 高于启动器应用条目常用的 0.5，这样首屏仍是「最近使用 → 插件命令」。
    public static let emptyQueryRelevance = 0.7

    /// 按查询打分
    ///
    /// 空查询不走模糊匹配，只返回每个插件至多一条入口。
    public static func matching(_ commands: [IndexedCommand], query: String) -> [CommandHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return emptyEntries(commands).map {
                CommandHit(command: $0, relevance: emptyQueryRelevance)
            }
        }

        let match = MatchQuery(trimmed)
        let hits: [CommandHit] = commands.compactMap { command in
            var bestScore = match.score(command.titleText)

            for kw in command.keywordTexts {
                let kwScore = match.score(kw) * 0.90
                if kwScore > bestScore { bestScore = kwScore }
            }

            guard bestScore > 0 else { return nil }
            return CommandHit(command: command, relevance: bestScore)
        }

        // 同一插件若已有具体功能命令（非 plugin.open.*）以更高或相同相关度命中，
        // 不再并列展示只打开外壳的 plugin.open.* 入口
        var bestSpecificByPlugin = [String: Double]()
        for hit in hits where CommandID.openedPluginID(in: hit.command.id) == nil {
            let pluginID = hit.command.descriptor.pluginID
            if hit.relevance > (bestSpecificByPlugin[pluginID] ?? 0) {
                bestSpecificByPlugin[pluginID] = hit.relevance
            }
        }
        let filteredHits = hits.filter { hit in
            guard let pluginID = CommandID.openedPluginID(in: hit.command.id),
                let bestSpecific = bestSpecificByPlugin[pluginID]
            else { return true }
            return hit.relevance > bestSpecific
        }

        // 同一插件下相同标题的命令（例如「打开插件」与同名功能命令），去重只留一条
        var seenBest = [String: CommandHit]()
        for hit in filteredHits {
            let key = "\(hit.command.descriptor.pluginID):\(hit.command.descriptor.title.lowercased())"
            if let existing = seenBest[key] {
                if hit.relevance > existing.relevance {
                    seenBest[key] = hit
                } else if hit.relevance == existing.relevance {
                    let hitIsOpen = CommandID.openedPluginID(in: hit.command.id) != nil
                    let existingIsOpen = CommandID.openedPluginID(in: existing.command.id) != nil
                    if !hitIsOpen && existingIsOpen {
                        seenBest[key] = hit
                    }
                }
            } else {
                seenBest[key] = hit
            }
        }
        var result: [CommandHit] = []
        var emitted = Set<String>()
        for hit in filteredHits {
            let key = "\(hit.command.descriptor.pluginID):\(hit.command.descriptor.title.lowercased())"
            if let best = seenBest[key], emitted.insert(key).inserted {
                result.append(best)
            }
        }
        return result
    }

    /// 每个插件取第一条声明了空查询入口的命令
    public static func emptyEntries(_ commands: [IndexedCommand]) -> [IndexedCommand] {
        var seen = Set<String>()
        var result: [IndexedCommand] = []
        for command in commands where command.descriptor.showsWhenQueryEmpty {
            if seen.insert(command.descriptor.pluginID).inserted {
                result.append(command)
            }
        }
        return result
    }
}
