// RankingStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
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

    private let log = QuickLog.module(LauncherModule.id)

    /// 延迟保存任务
    private var saveTask: Task<Void, Never>?

    /// 防抖保存间隔
    private static let saveDebounce = Duration.seconds(5)

    /// 存储文件路径
    private let storageURL: URL

    /// 初始化
    /// - Parameter storageURL: 存储路径。传 nil 用默认位置；测试传临时目录以获得无副作用的行为。
    init(storageURL: URL? = nil) {
        self.storageURL =
            storageURL
            ?? AppPaths.moduleData("launcher").appendingPathComponent("ranking.json")
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
        guard let data = try? Data(contentsOf: storageURL) else {
            log.debug("没有使用频率记录，按空记录启动")
            return
        }
        do {
            let counts = try JSONDecoder().decode([String: Int].self, from: data)
            usageCounts = counts
            maxCount = max(counts.values.max() ?? 1, 1)
            log.info("使用频率已加载，\(counts.count, privacy: .public) 个应用")
        } catch {
            log.error("使用频率解码失败，已按空记录继续：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 保存到磁盘
    func save() {
        do {
            let data = try JSONEncoder().encode(usageCounts)
            try data.write(to: storageURL)
            log.debug("使用频率已写入，\(self.usageCounts.count, privacy: .public) 个应用")
        } catch {
            log.error("使用频率写入失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 防抖保存（避免频繁磁盘写入）
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
}
