// RankingStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickPlatform

/// 使用频率排序存储
///
/// 记录每个应用的使用次数，用于搜索结果排序。
/// 数据持久化到 Application Support 目录。
@MainActor
final class RankingStore {

    /// 使用次数记录（bundleID → 使用次数）
    private var usageCounts: [String: Int] = [:]

    /// 最大使用次数（用于归一化评分）
    private var maxCount: Int = 1

    /// 存储文件路径
    private var storageURL: URL {
        AppPaths.moduleData("launcher").appendingPathComponent("ranking.json")
    }

    /// 记录一次使用
    /// - Parameter bundleID: 应用 Bundle ID
    func recordUsage(_ bundleID: String) {
        let count = (usageCounts[bundleID] ?? 0) + 1
        usageCounts[bundleID] = count
        if count > maxCount { maxCount = count }
        scheduleSave()
    }

    /// 获取应用的排序评分（0.0 ~ 1.0）
    /// - Parameter bundleID: 应用 Bundle ID
    /// - Returns: 归一化的使用频率评分
    func score(for bundleID: String) -> Double {
        guard let count = usageCounts[bundleID], maxCount > 0 else { return 0 }
        return Double(count) / Double(maxCount)
    }

    // MARK: - 持久化

    /// 从磁盘加载
    func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let counts = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return }
        usageCounts = counts
        maxCount = max(counts.values.max() ?? 1, 1)
    }

    /// 保存到磁盘
    func save() {
        guard let data = try? JSONEncoder().encode(usageCounts) else { return }
        try? data.write(to: storageURL)
    }

    /// 延迟保存定时器
    private var saveTimer: Timer?

    /// 防抖保存（避免频繁磁盘写入）
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.save()
            }
        }
    }
}
