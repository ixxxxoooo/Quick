// FavoritesStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 收藏应用存储
///
/// 管理用户收藏的应用列表，收藏的应用在搜索结果中优先显示。
///
/// 一行一个收藏，顺序由 `sort_order` 决定 —— 旧版整份数组重写 JSON，
/// 而「谁排在前面」只能靠数组下标维持；换成表之后顺序必须显式存下来，
/// 否则增删一次就可能因为排序不稳定而改变界面顺序。
@MainActor
final class FavoritesStore {

    /// 收藏的 Bundle ID 列表（按收藏顺序）
    private(set) var favoriteIDs: [String] = []

    private let log = QuickLog.plugin(LauncherPlugin.id)

    /// 存储句柄
    private let storage: PluginStorage

    /// 初始化并加载
    /// - Parameter storage: 由 AppCore 注入的存储句柄（测试传内存库）
    init(storage: PluginStorage) {
        self.storage = storage
        load()
    }

    /// 添加收藏
    /// - Parameter bundleID: 应用 Bundle ID
    func add(_ bundleID: String) {
        guard !favoriteIDs.contains(bundleID) else { return }
        do {
            // 新收藏排在最后：取值用当前最大 sort_order 加一，删过中间项也不会撞号
            let nextOrder =
                (try storage.database.scalarInt(
                    "SELECT COALESCE(MAX(sort_order), 0) + 1 AS value FROM favorites")) ?? 1
            try storage.database.execute(
                "INSERT INTO favorites (item_id, sort_order, created_at) VALUES (?, ?, ?)",
                [.text(bundleID), .int(nextOrder), .date(Date())])
        } catch {
            log.error("收藏写入失败：\(error)")
            // 写失败就按库里的真相回退，避免内存里出现一个没落库的收藏
            load()
            return
        }
        favoriteIDs.append(bundleID)
        log.info("已收藏应用 \(bundleID, privacy: .public)")
    }

    /// 移除收藏
    /// - Parameter bundleID: 应用 Bundle ID
    func remove(_ bundleID: String) {
        favoriteIDs.removeAll { $0 == bundleID }
        do {
            try storage.database.execute(
                "DELETE FROM favorites WHERE item_id = ?", [.text(bundleID)])
        } catch {
            log.error("取消收藏失败：\(error)")
            load()
            return
        }
        log.info("已取消收藏应用 \(bundleID, privacy: .public)")
    }

    /// 是否已收藏
    /// - Parameter bundleID: 应用 Bundle ID
    /// - Returns: 是否在收藏列表中
    func isFavorite(_ bundleID: String) -> Bool {
        favoriteIDs.contains(bundleID)
    }

    // MARK: - 持久化

    /// 从数据库加载
    func load() {
        do {
            favoriteIDs = try storage.database.query(
                "SELECT item_id FROM favorites ORDER BY sort_order ASC, created_at ASC"
            ).compactMap { $0.text("item_id") }
            log.info("收藏已加载，\(self.favoriteIDs.count, privacy: .public) 个应用")
        } catch {
            log.error("收藏读取失败，已按空记录继续：\(error)")
            favoriteIDs = []
        }
    }

    /// 把内存缓存刷成数据库里的真实内容
    ///
    /// 每次增删都已经落库了，这里只是退出前的「确保一致」。
    func save() {
        load()
    }
}
