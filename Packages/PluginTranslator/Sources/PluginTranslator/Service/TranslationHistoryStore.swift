// TranslationHistoryStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 一条翻译历史
struct TranslationHistoryItem: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let sourceText: String
    let resultText: String
    /// 源语言 tag
    let from: String
    /// 目标语言 tag
    let to: String
    let date: Date
}

/// 翻译历史存储
///
/// 走插件的键值存储（`PluginStorage`）：历史是**用户内容**，不是偏好，所以不放
/// `UserDefaults`（否则「重置设置」会连历史一起清掉）。整体作为一段 JSON 存取，
/// 上限封顶，重复的「原文 + 语言对」去重后提到最前。
@MainActor
final class TranslationHistoryStore {

    private let storage: PluginStorage
    private let key = "history"
    private let limit: Int

    private(set) var items: [TranslationHistoryItem] = []

    init(storage: PluginStorage, limit: Int = 50) {
        self.storage = storage
        self.limit = limit
        items = (try? storage.value([TranslationHistoryItem].self, forKey: key)) ?? []
    }

    /// 记录一次翻译（重复的原文 + 语言对提到最前，不重复记录）
    func record(source: String, result: String, from: String, to: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !result.isEmpty else { return }
        items.removeAll { $0.sourceText == trimmed && $0.from == from && $0.to == to }
        items.insert(
            TranslationHistoryItem(
                id: UUID(), sourceText: trimmed, resultText: result, from: from, to: to,
                date: Date()),
            at: 0
        )
        if items.count > limit { items = Array(items.prefix(limit)) }
        persist()
    }

    /// 清空历史
    func clear() {
        items = []
        persist()
    }

    private func persist() {
        do {
            try storage.set(items, forKey: key)
        } catch {
            QuickLog.plugin("translator").warning(
                "翻译历史写入失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
