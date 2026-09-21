// MatchText.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一条候选文本的匹配形态
///
/// 「规范化」和「打分」是两件事：前者贵（折叠大小写/变音符号/全角，还要转写拼音），
/// 而候选在一次搜索会话里不会变。所以候选多的时候（应用索引有上百条）先把它预处理成
/// `MatchText` 存起来（见 `AppEntry.matchText`），之后每次按键只走打分。
///
/// 候选只有个位数时不必预处理，直接用 `String.fuzzyScore`。
public struct MatchText: Sendable {

    /// 折叠后的原文
    let folded: String

    /// 拼音形态；不含汉字时为 `nil`
    let pinyin: Pinyin.Forms?

    public init(_ text: String) {
        self.folded = MatchText.fold(text)
        self.pinyin = Pinyin.forms(of: text)
    }

    /// 折叠大小写、变音符号与全角/半角 —— 之后比较只关心字符本身
    ///
    /// 全角那一项是给中文输入法的：没切到英文键盘时打出来的 `ｖｓｃ` 也得能命中。
    static func fold(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
    }
}

/// 一次搜索的查询词
///
/// 每次按键构造一次，然后拿它扫全部候选：查询词的折叠只做一遍，不在候选循环里重复。
public struct MatchQuery: Sendable {

    private let folded: String

    /// 查询词里有没有汉字
    ///
    /// 有汉字就说明用户直接打了中文，字面匹配已经表达了意图，不必再试拼音。
    private let hasHan: Bool

    public init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.folded = MatchText.fold(trimmed)
        self.hasHan = trimmed.containsHan
    }

    /// 查询词去掉首尾空白后是否为空
    public var isEmpty: Bool { folded.isEmpty }

    /// 是否匹配
    public func matches(_ candidate: MatchText) -> Bool { score(candidate) > 0 }

    /// 候选与查询词的相关度；`0` 表示不匹配
    public func score(_ candidate: MatchText) -> Double {
        guard !folded.isEmpty else { return 0 }

        let literal = Self.literalScore(candidate.folded, query: folded)

        // 查询词带汉字时字面就够了；候选不是中文时 candidate.pinyin 本来就是 nil。
        guard !hasHan, let pinyin = candidate.pinyin else { return literal }

        // 拼音的分要压在字面之下：用户打 `wx` 时，名字真就叫 WX 的那个该排在「微信」前面。
        // 全拼比首字母更明确，所以权重更大。
        let full = Self.literalScore(pinyin.latin, query: folded) * Self.fullPinyinWeight
        let initials = Self.literalScore(pinyin.initials, query: folded) * Self.initialsWeight
        return max(literal, full, initials)
    }

    // MARK: - 打分

    /// 字面的逐级打分：完全 `1.0` > 前缀 `0.9` > 包含 `0.7` > 子序列 `[0.35, 0.65]` > 不匹配 `0`
    ///
    /// 前三级的分值不能随便改：插件把它们当刻度用（例如片段标题再乘 0.8），改了就是动了全盘排序。
    private static func literalScore(_ target: String, query: String) -> Double {
        guard !target.isEmpty else { return 0 }

        if target == query { return 1.0 }
        if target.hasPrefix(query) { return 0.9 }
        if target.contains(query) { return 0.7 }

        // 先过一遍子序列再建字符数组：绝大多数候选连子序列都不是，不该为它们分配。
        guard containsSubsequence(target, query) else { return 0 }

        let targetChars = Array(target)
        let queryChars = Array(query)
        guard let run = bestRun(in: targetChars, query: queryChars) else { return 0 }

        let quality = run.quality(queryCount: queryChars.count, targetCount: targetChars.count)
        return subsequenceFloor + subsequenceRange * quality
    }

    /// 查询词的字符是否按顺序出现在候选里
    private static func containsSubsequence(_ target: String, _ query: String) -> Bool {
        var remaining = query.makeIterator()
        guard let first = remaining.next() else { return true }

        var wanted = first
        for character in target {
            guard character == wanted else { continue }
            guard let next = remaining.next() else { return true }
            wanted = next
        }
        return false
    }

    /// 一次子序列匹配的形状
    private struct Run {
        /// 全部命中字符累计到的加分
        let bonus: Int

        /// 质量 0 ~ 1
        ///
        /// 每个字符满分 3 分（1 分基础 + 2 分落在词首，紧邻上一个命中再 +1 ——
        /// 「词首」和「紧邻」不可能同时成立，所以 3 就是上限）。
        /// 再乘一个长度系数：查询词占候选的比例越大，说明候选越像这个查询词，
        /// 免得一个长句子里恰好有几个词首对上就拿到高分。
        func quality(queryCount: Int, targetCount: Int) -> Double {
            let density = Double(bonus) / Double(queryCount * Run.maxBonusPerCharacter)
            let lengthFactor = 0.5 + 0.5 * Double(queryCount) / Double(targetCount)
            return density * lengthFactor
        }

        /// 单个命中字符能拿到的最高加分
        static let maxBonusPerCharacter = 3
        /// 落在词首的额外加分
        static let wordStartBonus = 2
        /// 紧邻上一个命中的额外加分
        static let adjacentBonus = 1
    }

    /// 在所有可能的起点里挑质量最高的一次子序列匹配
    ///
    /// 从每个「可能对上首字符」的位置贪心往后扫一遍。候选名都很短（应用名、标题），
    /// 这点枚举换来的是 `vsc` 命中 `Visual Studio Code` 这件事终于能和乱序子序列区分开。
    private static func bestRun(in target: [Character], query: [Character]) -> Run? {
        guard let first = query.first else { return nil }

        var best: Run?
        var bestQuality = 0.0

        for start in target.indices where target[start] == first {
            var cursor = start
            var bonus = 0
            var previousMatch = -2
            var matchedAll = true

            for character in query {
                while cursor < target.count, target[cursor] != character { cursor += 1 }
                guard cursor < target.count else {
                    matchedAll = false
                    break
                }

                bonus += 1
                if isWordStart(in: target, at: cursor) { bonus += Run.wordStartBonus }
                if cursor == previousMatch + 1 { bonus += Run.adjacentBonus }

                previousMatch = cursor
                cursor += 1
            }
            guard matchedAll else { continue }

            let run = Run(bonus: bonus)
            let quality = run.quality(queryCount: query.count, targetCount: target.count)
            if quality > bestQuality {
                bestQuality = quality
                best = run
            }
        }
        return best
    }

    /// 该位置是不是一个词的开头：候选首位，或前一个字符是分隔符
    private static func isWordStart(in target: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = target[index - 1]
        return !previous.isLetter && !previous.isNumber
    }

    // MARK: - 刻度

    /// 子序列命中的下界，高于「不匹配」的 0
    private static let subsequenceFloor = 0.35
    /// 子序列命中的跨度，上界 0.65 低于「包含」的 0.7
    private static let subsequenceRange = 0.30
    /// 全拼命中的权重，压在字面之下
    private static let fullPinyinWeight = 0.85
    /// 拼音首字母命中的权重：比全拼模糊，所以更低
    private static let initialsWeight = 0.75
}
