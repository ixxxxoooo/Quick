// FavoritesStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickPlatform

/// 收藏应用存储
///
/// 管理用户收藏的应用列表，收藏的应用在搜索结果中优先显示。
@MainActor
final class FavoritesStore {

    /// 收藏的 Bundle ID 列表
    private(set) var favoriteIDs: [String] = []

    /// 存储文件路径
    private var storageURL: URL {
        AppPaths.moduleData("launcher").appendingPathComponent("favorites.json")
    }

    /// 添加收藏
    /// - Parameter bundleID: 应用 Bundle ID
    func add(_ bundleID: String) {
        guard !favoriteIDs.contains(bundleID) else { return }
        favoriteIDs.append(bundleID)
        save()
    }

    /// 移除收藏
    /// - Parameter bundleID: 应用 Bundle ID
    func remove(_ bundleID: String) {
        favoriteIDs.removeAll { $0 == bundleID }
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
        guard let data = try? Data(contentsOf: storageURL),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        favoriteIDs = ids
    }

    /// 保存到磁盘
    private func save() {
        guard let data = try? JSONEncoder().encode(favoriteIDs) else { return }
        try? data.write(to: storageURL)
    }
}
