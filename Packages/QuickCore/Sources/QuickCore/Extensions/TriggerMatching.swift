// TriggerMatching.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 插件触发词的匹配与剥离
///
/// 插件的 `searchItems` 通常先判断「用户在不在问这件事」（触发词），再拿真正的
/// 查询词去过滤数据。这两步都容易写错，所以统一在这里：
///
/// **为什么不能直接用 `contains`。** 用 `contains` 判断触发词会让大量无关查询命中：
/// `email` 命中 `ai`、`clipboard` 命中 `ip`、`export` 命中 `port`、`memory` 命中 `memo`。
/// 结果就是打 `clipboard` 时同时冒出「网络工具」。
///
/// **为什么不能统一用前缀匹配。** 前缀会救回上面的例子，但 `memory` 仍然命中 `memo`。
/// 所以拉丁字母触发词按**整词**匹配，中文触发词按**前缀**匹配 ——
/// 中文没有词边界，`天气北京` 必须能命中 `天气`；拉丁字母有词边界，
/// `memory` 不该命中 `memo`。
///
/// 整词规则的代价是「打一半进不来」：`deep` 到不了触发词 `deepseek`。要边打边收窄的插件
/// （AI 聚合的 Provider 名就是典型）用 `matchesAnyTriggerIncludingPrefix(_:minimumPrefix:)`，
/// 它额外放行前缀，但要求查询词够长，见那个方法的说明。
public extension String {

    /// 是否命中任一触发词
    ///
    /// - Parameter triggers: 触发词列表（小写或大写都行，比较时统一转小写）
    /// - Returns: 是否命中
    func matchesAnyTrigger(_ triggers: [String]) -> Bool {
        !matchedTrigger(in: triggers).isEmpty
    }

    /// 是否命中任一触发词，**或者**是某个触发词的开头
    ///
    /// 给「查询词本身就是名字的一部分」的插件用：AI 聚合要能打 `deep` 就找到 DeepSeek、
    /// 打 `chatgp` 就找到 ChatGPT。整词规则（`matchesAnyTrigger`）做不到这件事 ——
    /// 它为了保护 `ai` / `memo` 这类短触发词而不接受前缀。
    ///
    /// **长度下限不能去掉。** 没有 `minimumPrefix` 的话，打一个字母就会命中一片
    /// （`a` → `ai`、`g` → `gpt`、`d` → `deepseek`），首屏立刻变成噪音。
    /// 三个字符是「用户已经知道自己在找哪个名字」的下限。
    ///
    /// - Parameters:
    ///   - triggers: 触发词列表（大小写不敏感）
    ///   - minimumPrefix: 前缀匹配所需的最少字符数，默认 3
    /// - Returns: 是否命中
    func matchesAnyTriggerIncludingPrefix(_ triggers: [String], minimumPrefix: Int = 3) -> Bool {
        if matchesAnyTrigger(triggers) { return true }

        let query = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.count >= minimumPrefix else { return false }

        return triggers.contains { $0.lowercased().hasPrefix(query) }
    }

    /// 命中并剥离触发词后剩下的查询词
    ///
    /// 剩下的部分才是真正要拿去过滤数据的词。空字符串表示用户只打了触发词本身
    /// —— 这时应当按「没有查询条件」处理（列出全部），而不是拿触发词去过滤
    /// （那永远匹配不到任何数据）。
    ///
    /// - Parameter triggers: 触发词列表
    /// - Returns: 剥离触发词并去掉首尾空白后的查询词
    func removingTrigger(_ triggers: [String]) -> String {
        let trigger = matchedTrigger(in: triggers)
        guard !trigger.isEmpty else { return trimmingCharacters(in: .whitespacesAndNewlines) }

        var remainder = trimmingCharacters(in: .whitespacesAndNewlines)
        // 触发词可能在开头（`天气 北京`）或作为某个词出现（`看下 天气 北京`），
        // 两种都要能剥掉，且只剥第一处。
        if let range = remainder.range(of: trigger, options: [.caseInsensitive]) {
            remainder.removeSubrange(range)
        }
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 实际命中的那个触发词（没有命中则返回空串）
    ///
    /// 返回具体命中项而不是 Bool，是因为调用方需要知道该剥掉哪一个。
    ///
    /// - Parameter triggers: 触发词列表
    /// - Returns: 命中的触发词；未命中返回 `""`
    func matchedTrigger(in triggers: [String]) -> String {
        let query = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return "" }

        // 词表按长度倒序：`lock screen` 要先于 `lock` 试，否则只会剥掉短的、
        // 把 `screen` 留在查询词里。
        for trigger in triggers.map({ $0.lowercased() }).sorted(by: { $0.count > $1.count }) {
            guard !trigger.isEmpty else { continue }
            if Self.isTriggerMatch(query: query, trigger: trigger) {
                return trigger
            }
        }
        return ""
    }

    /// 单个触发词是否命中
    ///
    /// 含中日韩字符的触发词按「前缀或子串」匹配；纯拉丁触发词按「整词」匹配 ——
    /// 而且整词是指**连续的词组**，否则 `lock screen` 这种多词触发词永远命中不了
    /// （没有任何一个单词等于 `lock screen`）。
    private static func isTriggerMatch(query: String, trigger: String) -> Bool {
        if trigger.containsCJK {
            return query.hasPrefix(trigger) || query.contains(trigger)
        }

        let queryWords = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let triggerWords = trigger.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard !triggerWords.isEmpty, queryWords.count >= triggerWords.count else { return false }

        for start in 0...(queryWords.count - triggerWords.count) {
            if Array(queryWords[start..<(start + triggerWords.count)]) == triggerWords {
                return true
            }
        }
        return false
    }

    /// 是否含汉字
    ///
    /// 比 `containsCJK` 窄：假名与谚文也算东亚文字，但转不成拼音，所以不算汉字。
    var containsHan: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,  // 扩展 A
                0x4E00...0x9FFF,  // 基本区
                0xF900...0xFAFF:  // 兼容表意
                return true
            default:
                return false
            }
        }
    }

    /// 是否含中日韩字符
    var containsCJK: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF,  // 平假名 / 片假名
                0x3400...0x4DBF,  // 扩展 A
                0x4E00...0x9FFF,  // 基本区
                0xF900...0xFAFF,  // 兼容表意
                0xAC00...0xD7AF:  // 谚文
                return true
            default:
                return false
            }
        }
    }
}
