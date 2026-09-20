// ClipboardStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import QuickPlatform

/// 剪贴板历史存储
///
/// 管理剪贴板历史条目的内存缓存和磁盘持久化。
/// 自动去重、限制条目数量。
@MainActor
@Observable
final class ClipboardStore {

    /// 所有条目（按时间倒序）
    private(set) var entries: [ClipboardEntry] = []

    /// 最大保存条目数
    private let maxEntries = 500

    private let log = QuickLog.module(ClipboardModule.id)

    /// 落盘防抖任务
    private var saveTask: Task<Void, Never>?

    /// 落盘防抖间隔
    ///
    /// 剪贴板可能连续变化多次，每次都写盘既浪费又会互相打断。
    private static let saveDebounce = Duration.seconds(2)

    /// 存储文件路径
    private let storageURL: URL

    /// 初始化
    /// - Parameter storageURL: 存储路径。传 nil 用默认位置；测试传临时目录以获得无副作用的行为。
    init(storageURL: URL? = nil) {
        self.storageURL =
            storageURL
            ?? AppPaths.moduleData("clipboard").appendingPathComponent("history.json")
    }

    /// 添加新条目
    /// - Parameter entry: 剪贴板条目
    func add(_ entry: ClipboardEntry) {
        // 去重：相同内容不重复记录
        if entry.type == .image {
            // 图片按数据内容去重
            entries.removeAll { $0.type == .image && $0.imageData == entry.imageData }
        } else {
            entries.removeAll { $0.text == entry.text }
        }
        entries.insert(entry, at: 0)

        // 限制数量（保留置顶和收藏）
        if entries.count > maxEntries {
            entries =
                entries.filter { $0.isPinned || $0.isFavorite }
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

    /// 收藏的条目
    var favorites: [ClipboardEntry] {
        entries.filter(\.isFavorite)
    }

    /// 按类型筛选
    func entries(ofType type: ClipboardEntry.ContentType) -> [ClipboardEntry] {
        entries.filter { $0.type == type }
    }

    /// 图片条目
    var imageEntries: [ClipboardEntry] {
        entries.filter { $0.type == .image }
    }

    /// 搜索条目
    /// - Parameter query: 搜索关键词
    /// - Returns: 匹配的条目
    func search(_ query: String) -> [ClipboardEntry] {
        guard !query.isEmpty else { return entries }
        let lower = query.lowercased()
        return entries.filter {
            $0.text.lowercased().contains(lower)
                || $0.preview.lowercased().contains(lower)
        }
    }

    // MARK: - 持久化

    func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            log.debug("没有剪贴板历史文件，按空历史启动")
            return
        }
        do {
            entries = try JSONDecoder().decode([ClipboardEntry].self, from: data)
            log.info("剪贴板历史已加载，\(self.entries.count, privacy: .public) 条")
        } catch {
            // 数据损坏时不能让整个模块起不来：记一条 error，按空历史继续。
            log.error("剪贴板历史解码失败，已按空历史继续：\(error.localizedDescription, privacy: .public)")
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storageURL)
            log.debug("剪贴板历史已写入，\(self.entries.count, privacy: .public) 条")
        } catch {
            log.error("剪贴板历史写入失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
}
