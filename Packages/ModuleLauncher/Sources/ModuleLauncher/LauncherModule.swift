// LauncherModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 应用启动器模块
///
/// 核心模块，提供主搜索入口。扫描系统已安装应用，
/// 支持模糊搜索、拼音匹配、使用频率排序、收藏等功能。
@MainActor
public final class LauncherModule: QuickModule {

    public static let id = "launcher"
    public static let name = "应用启动器"
    public static let icon = "magnifyingglass"

    public var isEnabled = true

    private let log = QuickLog.module(LauncherModule.id)

    /// 应用索引（由 AppCore 注入）
    private let appIndex: AppIndex

    /// 使用频率排序
    private let rankingStore = RankingStore()

    /// 收藏应用
    private let favoritesStore = FavoritesStore()

    /// 初始化启动器模块
    /// - Parameter appIndex: 应用索引服务
    public init(appIndex: AppIndex) {
        self.appIndex = appIndex
    }

    // MARK: - QuickModule 协议

    /// 空查询时不要返回全部应用，避免首屏加载过多图标
    public func searchItems(query: String) async -> [SearchableItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // 空查询：仅返回收藏或高频前几项
            let favorites = Set(favoritesStore.favoriteIDs)
            let apps = appIndex.apps.filter { favorites.contains($0.bundleID) }.prefix(8)
            let source = apps.isEmpty ? Array(appIndex.apps.prefix(8)) : Array(apps)
            return source.map { entry in
                SearchableItem(
                    id: "launcher.\(entry.id)",
                    moduleID: Self.id,
                    title: entry.name,
                    subtitle: entry.isSystemApp ? "系统应用" : "应用程序",
                    icon: "app.fill",
                    iconType: .appIcon(entry.path),
                    relevance: 0.5,
                    action: { [weak self] in
                        entry.launch()
                        self?.rankingStore.recordUsage(entry.bundleID)
                        EventBus.shared.post(HidePaletteEvent())
                    }
                )
            }
        }

        let results = appIndex.search(query: trimmed)
        return results.prefix(20).map { entry in
            let ranking = rankingStore.score(for: entry.bundleID)
            let baseScore = entry.name.fuzzyScore(trimmed)
            let finalScore = baseScore * 0.7 + ranking * 0.3

            return SearchableItem(
                id: "launcher.\(entry.id)",
                moduleID: Self.id,
                title: entry.name,
                subtitle: entry.isSystemApp ? "系统应用" : "应用程序",
                icon: "app.fill",
                iconType: .appIcon(entry.path),
                relevance: finalScore,
                action: { [weak self] in
                    entry.launch()
                    self?.rankingStore.recordUsage(entry.bundleID)
                    EventBus.shared.post(HidePaletteEvent())
                }
            )
        }
    }

    public func makeView() -> AnyView {
        AnyView(LauncherView(module: self))
    }

    public func makeSettingsView() -> AnyView? {
        nil
    }

    public func activate() {
        rankingStore.load()
        favoritesStore.load()
        log.notice(
            """
            模块已激活：收藏 \(self.favoritesStore.favoriteIDs.count, privacy: .public) 个，\
            索引内 \(self.appIndex.apps.count, privacy: .public) 个应用
            """)
    }

    public func deactivate() {
        rankingStore.save()
        log.notice("模块已停用，使用频率已落盘")
    }
}
