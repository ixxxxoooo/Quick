// MatchHighlighter.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 结果标题里「命中了哪几个字」的计算
///
/// 纯逻辑、只依赖 Foundation，可脱离界面单测。规则：
/// 1. 查询按空白拆成词，每个词在标题里找**第一处**不区分大小写、不区分音标的子串；
/// 2. 只有一个词且它不是子串时，退回「按顺序出现的字符」（缩写匹配：`vsc` → **V**isual **S**tudio **C**ode）；
/// 3. 重叠 / 相邻的命中合并，调用方拿到的是互不相交、按位置升序的区间。
enum MatchHighlighter {

    /// 比较选项：不区分大小写与音标
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// 命中区间（升序、互不相交）
    static func ranges(in title: String, query: String) -> [Range<String.Index>] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty, !title.isEmpty else { return [] }

        var found: [Range<String.Index>] = []
        var allSubstring = true
        for token in tokens {
            if let range = title.range(of: token, options: options) {
                found.append(range)
            } else {
                allSubstring = false
            }
        }

        if !allSubstring, tokens.count == 1, let subsequence = subsequenceRanges(in: title, token: tokens[0]) {
            return merge(subsequence)
        }
        return merge(found)
    }

    /// 带高亮的标题
    ///
    /// 命中的部分加粗；没有命中（或查询为空）时返回原样文本。
    static func attributed(title: String, query: String) -> AttributedString {
        var result = AttributedString(title)
        for range in ranges(in: title, query: query) {
            if let attributedRange = Range(range, in: result) {
                result[attributedRange].inlinePresentationIntent = .stronglyEmphasized
            }
        }
        return result
    }

    // MARK: - 内部

    /// 单个词作为「有序字符子序列」出现在标题里时，每个字符所在的区间
    ///
    /// 每个字符优先落在**词首**（缩写的习惯：`vsc` 指 Visual Studio Code 的三个首字母，
    /// 而不是 Visual 里的 s），词首找不到再退回任意位置。
    private static func subsequenceRanges(in title: String, token: String) -> [Range<String.Index>]? {
        var result: [Range<String.Index>] = []
        var cursor = title.startIndex
        for character in token {
            let needle = String(character)
            guard cursor < title.endIndex else { return nil }
            let window = cursor..<title.endIndex
            var chosen: Range<String.Index>?
            var searchFrom = window
            while let candidate = title.range(of: needle, options: options, range: searchFrom) {
                if chosen == nil { chosen = candidate }
                if isWordStart(candidate.lowerBound, in: title) {
                    chosen = candidate
                    break
                }
                guard candidate.upperBound < title.endIndex else { break }
                searchFrom = candidate.upperBound..<title.endIndex
            }
            guard let hit = chosen else { return nil }
            result.append(hit)
            cursor = hit.upperBound
        }
        return result
    }

    /// 该位置是否是词首（标题开头，或前一个字符不是字母 / 数字）
    private static func isWordStart(_ index: String.Index, in title: String) -> Bool {
        guard index > title.startIndex else { return true }
        let previous = title[title.index(before: index)]
        return !(previous.isLetter || previous.isNumber)
    }

    /// 排序并合并重叠 / 相邻的区间
    private static func merge(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        var merged: [Range<String.Index>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
