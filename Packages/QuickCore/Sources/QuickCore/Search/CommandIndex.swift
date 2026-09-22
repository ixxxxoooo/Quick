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

    /// 标题、插件名、关键词、副标题的匹配形态
    public let fields: [MatchText]

    public var id: String { descriptor.id }

    /// 用描述符建索引
    public init(_ descriptor: CommandDescriptor) {
        self.descriptor = descriptor
        var texts = [MatchText(descriptor.title), MatchText(descriptor.pluginName)]
        texts.append(contentsOf: descriptor.keywords.map { MatchText($0) })
        if let subtitle = descriptor.subtitle, !subtitle.isEmpty {
            texts.append(MatchText(subtitle))
        }
        self.fields = texts
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
        return commands.compactMap { command in
            let score = command.fields.map { match.score($0) }.max() ?? 0
            guard score > 0 else { return nil }
            return CommandHit(command: command, relevance: score)
        }
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
