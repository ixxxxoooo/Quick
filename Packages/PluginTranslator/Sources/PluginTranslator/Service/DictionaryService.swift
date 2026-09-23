// DictionaryService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreServices
import Foundation

/// 系统词典查询
///
/// 用 macOS 内置的 `DictionaryServices`（`DCSCopyTextDefinition`）查词：离线、零依赖、
/// 走系统已安装的词典（简体中文、牛津英汉等），拿到音标与中英释义。查询结果按词缓存，
/// 同一个词不重复问系统。
@MainActor
final class DictionaryService {

    /// 词 → 词条（`nil` 表示查过但没命中，同样缓存，避免反复查空）
    private var cache: [String: DictionaryEntry?] = [:]

    /// 查词
    ///
    /// - Parameter word: 待查文本（英文单词或中文词）
    /// - Returns: 结构化词条；系统词典查不到时返回 `nil`
    func lookup(_ word: String) -> DictionaryEntry? {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return nil }
        if let cached = cache[clean] { return cached }
        let entry = Self.systemLookup(clean)
        cache[clean] = entry
        return entry
    }

    private static func systemLookup(_ clean: String) -> DictionaryEntry? {
        let range = CFRangeMake(0, clean.utf16.count)
        guard let result = DCSCopyTextDefinition(nil, clean as CFString, range) else { return nil }
        let raw = result.takeRetainedValue() as String
        let entry = DictionaryParser.parse(raw: raw, query: clean)

        // 系统词典对个别英文词会命中中文条目（例如 `run` 命中拼音 rún 的「瞤」）。
        // 查询是纯拉丁、词头却是 CJK 时判为误命中，交给翻译兜底。
        if Self.isLatinWord(clean), Self.containsCJK(entry.word) { return nil }
        return entry.isEmpty ? nil : entry
    }

    private static func isLatinWord(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isLetter && $0.isASCII }
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }
}
