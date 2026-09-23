// DictionaryEntry.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一条词义
public struct DictionarySense: Sendable, Equatable {
    /// 词性缩写（`n.` / `v.` …），没有则为空
    public let pos: String
    /// 释义文本
    public let meaning: String

    public init(pos: String, meaning: String) {
        self.pos = pos
        self.meaning = meaning
    }
}

/// 一个词条
public struct DictionaryEntry: Sendable, Equatable {
    public let word: String
    /// 音标（形如 `BrE …, AmE …`），没有则为空
    public let phonetic: String
    public let senses: [DictionarySense]
    public let examples: [String]
    /// 原始释义文本（解析不出结构时的兜底展示）
    public let raw: String

    public init(
        word: String,
        phonetic: String,
        senses: [DictionarySense],
        examples: [String],
        raw: String
    ) {
        self.word = word
        self.phonetic = phonetic
        self.senses = senses
        self.examples = examples
        self.raw = raw
    }

    public var isEmpty: Bool { senses.isEmpty && examples.isEmpty && raw.isEmpty }

    /// 首条释义（给内联结果用）
    public var briefMeaning: String? { senses.first?.meaning }

    /// 可复制 / 展示的整条文本
    public var displayText: String {
        var lines: [String] = [word]
        if !phonetic.isEmpty { lines.append(phonetic) }
        for sense in senses {
            lines.append(sense.pos.isEmpty ? sense.meaning : "\(sense.pos) \(sense.meaning)")
        }
        return lines.joined(separator: "\n")
    }

    public static func empty(word: String) -> DictionaryEntry {
        DictionaryEntry(word: word, phonetic: "", senses: [], examples: [], raw: "")
    }
}

/// 把 macOS 系统词典返回的文本解析成结构化词条
///
/// 系统词典（`DCSCopyTextDefinition`）返回的是带标记的单行文本，形如：
/// `apple | BrE ˈapl, AmE ˈæp(ə)l | noun (fruit) 苹果 píngguǒ▸ the apple of sb's eye 掌上明珠`
/// —— `|` 分隔词头 / 音标 / 释义，`▸` 分隔例句，`①②` 分隔多个义项。
/// 解析纯逻辑、可单测；词典本身由 `DictionaryService` 提供。
public enum DictionaryParser {

    private static let posMap: [(full: String, abbr: String)] = [
        ("auxiliary verb", "aux."), ("modal verb", "modal"),
        ("noun", "n."), ("verb", "v."), ("adjective", "adj."), ("adverb", "adv."),
        ("preposition", "prep."), ("conjunction", "conj."), ("pronoun", "pron."),
        ("interjection", "interj."), ("exclamation", "excl."), ("determiner", "det."),
        ("numeral", "num."), ("article", "art.")
    ]

    private static let senseMarkers: Set<Character> = Set("①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳")

    /// 解析
    ///
    /// - Parameters:
    ///   - raw: 系统词典返回的原始文本
    ///   - query: 用户查询的词（解析不出词头时用它）
    /// - Returns: 结构化词条；`raw` 为空时返回空词条
    public static func parse(raw: String, query: String) -> DictionaryEntry {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty(word: query) }

        let parts = trimmed.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        let word: String
        let phonetic: String
        let body: String
        if parts.count >= 3 {
            word = parts[0]
            phonetic = parts[1]
            body = parts[2...].joined(separator: " | ")
        } else if parts.count == 2 {
            word = parts[0]
            phonetic = ""
            body = parts[1]
        } else {
            word = query
            phonetic = ""
            body = trimmed
        }

        // 例句：`▸` 之后都是例句，第一段是释义
        let segments = body.components(separatedBy: "▸").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let definitionPart = segments.first ?? ""
        let examples = segments.dropFirst().filter { !$0.isEmpty }

        let (pos, rest) = extractPOS(definitionPart)
        let senses = splitSenses(rest, pos: pos)

        return DictionaryEntry(
            word: word,
            phonetic: phonetic,
            senses: senses,
            examples: Array(examples),
            raw: trimmed
        )
    }

    /// 从释义开头剥出词性
    private static func extractPOS(_ text: String) -> (abbr: String, rest: String) {
        let lower = text.lowercased()
        for entry in posMap where lower.hasPrefix(entry.full + " ") {
            let rest = String(text.dropFirst(entry.full.count))
                .trimmingCharacters(in: .whitespaces)
            return (entry.abbr, rest)
        }
        if let match = text.range(
            of: #"^(n|v|vt|vi|adj|adv|prep|conj|pron|interj|det|num|art)\."#,
            options: .regularExpression
        ) {
            let abbr = String(text[match])
            let rest = String(text[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (abbr, rest)
        }
        return ("", text)
    }

    /// 按 `①②…` 切分义项
    private static func splitSenses(_ text: String, pos: String) -> [DictionarySense] {
        var pieces: [String] = []
        var current = ""
        for ch in text {
            if senseMarkers.contains(ch) {
                let piece = current.trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty { pieces.append(piece) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { pieces.append(tail) }

        let cleaned =
            pieces
            .map { collapseWhitespace($0) }
            .filter { !$0.isEmpty }
        if cleaned.isEmpty {
            let fallback = collapseWhitespace(text)
            return fallback.isEmpty ? [] : [DictionarySense(pos: pos, meaning: fallback)]
        }
        return cleaned.map { DictionarySense(pos: pos, meaning: $0) }
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
