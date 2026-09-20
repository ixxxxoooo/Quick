// FavoritesStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import QuickPlatform

/// 收藏应用存储
///
/// 管理用户收藏的应用列表，收藏的应用在搜索结果中优先显示。
@MainActor
final class FavoritesStore {

    /// 收藏的 Bundle ID 列表
    private(set) var favoriteIDs: [String] = []

    private let log = QuickLog.module(LauncherModule.id)

    /// 存储文件路径
    private let storageURL: URL

    /// 初始化
    /// - Parameter storageURL: 存储路径。传 nil 用默认位置；测试传临时目录以获得无副作用的行为。
    init(storageURL: URL? = nil) {
        self.storageURL =
            storageURL
            ?? AppPaths.moduleData("launcher").appendingPathComponent("favorites.json")
    }

    /// 添加收藏
    /// - Parameter bundleID: 应用 Bundle ID
    func add(_ bundleID: String) {
        guard !favoriteIDs.contains(bundleID) else { return }
        favoriteIDs.append(bundleID)
        log.info("已收藏应用 \(bundleID, privacy: .public)")
        save()
    }

    /// 移除收藏
    /// - Parameter bundleID: 应用 Bundle ID
    func remove(_ bundleID: String) {
        favoriteIDs.removeAll { $0 == bundleID }
        log.info("已取消收藏应用 \(bundleID, privacy: .public)")
        save()
    }

    /// 是否已收藏
    /// - Parameter bundleID: 应用 Bundle ID
    /// - Returns: 是否在收藏列表中
    func isFavorite(_ bundleID: String) -> Bool {
        favoriteIDs.contains(bundleID)
    }

    // MARK: - 持久化

    /// 从磁盘加载
    func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            log.debug("没有收藏记录，按空记录启动")
            return
        }
        do {
            favoriteIDs = try JSONDecoder().decode([String].self, from: data)
            log.info("收藏已加载，\(self.favoriteIDs.count, privacy: .public) 个应用")
        } catch {
            log.error("收藏解码失败，已按空记录继续：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 保存到磁盘
    func save() {
        do {
            let data = try JSONEncoder().encode(favoriteIDs)
            try data.write(to: storageURL)
            log.debug("收藏已写入，\(self.favoriteIDs.count, privacy: .public) 个应用")
        } catch {
            log.error("收藏写入失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
