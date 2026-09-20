// ClipboardStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickPlatform

/// 剪贴板历史存储
///
/// 管理剪贴板历史条目的内存缓存和磁盘持久化。
/// 自动去重、限制条目数量。
@MainActor
final class ClipboardStore: Observable {

    /// 所有条目（按时间倒序）
    private(set) var entries: [ClipboardEntry] = []

    /// 最大保存条目数
    private let maxEntries = 500

    /// 存储文件路径
    private var storageURL: URL {
        AppPaths.moduleData("clipboard").appendingPathComponent("history.json")
    }

    /// 添加新条目
    /// - Parameter entry: 剪贴板条目
    func add(_ entry: ClipboardEntry) {
        // 去重：相同内容不重复记录（更新时间戳）
        entries.removeAll { $0.text == entry.text }
        entries.insert(entry, at: 0)

        // 限制数量（保留置顶和收藏）
        if entries.count > maxEntries {
            entries = entries.filter { $0.isPinned || $0.isFavorite }
                + entries.filter { !$0.isPinned && !$0.isFavorite }.prefix(maxEntries)
        }

        scheduleSave()
    }

    /// 删除条目
    /// - Parameter id: 条目 ID
    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        scheduleSave()
    }

    /// 清空所有历史（保留收藏和置顶）
    func clearHistory() {
        entries = entries.filter { $0.isFavorite || $0.isPinned }
        scheduleSave()
    }

    /// 切换收藏状态
    /// - Parameter id: 条目 ID
    func toggleFavorite(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isFavorite.toggle()
        scheduleSave()
    }

    /// 搜索条目
    /// - Parameter query: 搜索关键词
    /// - Returns: 匹配的条目
    func search(_ query: String) -> [ClipboardEntry] {
        guard !query.isEmpty else { return entries }
        let lower = query.lowercased()
        return entries.filter { $0.text.lowercased().contains(lower) }
    }

    // MARK: - 持久化

    func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data)
        else { return }
        entries = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storageURL)
    }

    private var saveTimer: Timer?

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.save() }
        }
    }
}
