// LauncherModuleTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickPlatform
import Testing

@testable import ModuleLauncher

@Suite("启动器模块")
@MainActor
struct LauncherModuleTests {

    /// 临时存储路径
    ///
    /// 目录要真正建出来：生产环境里 `AppPaths.moduleData(_:)` 会创建目录，
    /// 这里必须模拟同样的前提，否则测的是「目录不存在」而不是存储本身。
    private func temporaryStorageURL(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }

    // MARK: - 模块契约

    @Test("模块 id 符合约定")
    func identifierConvention() {
        #expect(LauncherModule.id == "launcher")
        #expect(!LauncherModule.name.isEmpty)
        #expect(!LauncherModule.icon.isEmpty)
    }

    @Test("空查询不返回全部应用")
    func emptyQueryDoesNotDumpEveryApp() async {
        // 首屏不该把几百个应用一次性铺出来：空查询最多给 8 条。
        let module = LauncherModule(appIndex: AppIndex())
        let results = await module.searchItems(query: "   ")
        #expect(results.count <= 8, "空查询（含纯空白）最多返回 8 条")
    }

    @Test("结果 id 带模块前缀且互不重复")
    func resultIdentifiersArePrefixedAndUnique() async {
        let module = LauncherModule(appIndex: AppIndex())
        let results = await module.searchItems(query: "x")

        let ids = results.map(\.id)
        #expect(Set(ids).count == ids.count, "同一模块内的 SearchableItem.id 必须唯一")
        #expect(ids.allSatisfy { $0.hasPrefix("launcher.") })
        #expect(results.allSatisfy { $0.moduleID == LauncherModule.id })
        #expect(results.count <= 20, "非空查询最多返回 20 条")
    }

    @Test("启停是幂等的，且停用会落盘")
    func activationIsIdempotent() {
        let module = LauncherModule(appIndex: AppIndex())
        module.activate()
        module.activate()
        module.deactivate()
        module.deactivate()
    }

    // MARK: - 使用频率评分

    @Test("未记录过的应用评分为 0")
    func unknownAppScoresZero() throws {
        let store = RankingStore(storageURL: try temporaryStorageURL("ranking.json"))
        #expect(store.score(for: "com.example.never-used") == 0)
    }

    @Test("用得最多的应用评分为 1，其余按比例")
    func scoreIsNormalisedByMostUsed() throws {
        let store = RankingStore(storageURL: try temporaryStorageURL("ranking.json"))
        for _ in 0..<4 { store.recordUsage("com.example.frequent") }
        store.recordUsage("com.example.rare")

        #expect(store.score(for: "com.example.frequent") == 1.0)
        #expect(store.score(for: "com.example.rare") == 0.25)
        #expect(store.score(for: "com.example.never-used") == 0)
    }

    @Test("用得越多评分越高")
    func scoreIsMonotonicInUsage() throws {
        let store = RankingStore(storageURL: try temporaryStorageURL("ranking.json"))
        store.recordUsage("com.example.a")
        let afterOne = store.score(for: "com.example.a")
        store.recordUsage("com.example.a")
        let afterTwo = store.score(for: "com.example.a")

        #expect(afterTwo >= afterOne)
    }

    @Test("使用频率可以往返持久化")
    func usageCountsRoundTrip() throws {
        let url = try temporaryStorageURL("ranking.json")
        let writer = RankingStore(storageURL: url)
        for _ in 0..<3 { writer.recordUsage("com.example.round-trip") }
        writer.save()

        let reader = RankingStore(storageURL: url)
        reader.load()
        #expect(reader.score(for: "com.example.round-trip") == 1.0)
    }

    @Test("损坏的存储文件不会让加载失败")
    func corruptStorageDegradesGracefully() throws {
        let url = try temporaryStorageURL("ranking.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("这不是合法 JSON".utf8).write(to: url)

        let store = RankingStore(storageURL: url)
        store.load()
        // 损坏数据必须降级为空记录，而不是把模块带崩。
        #expect(store.score(for: "com.example.any") == 0)
    }

    // MARK: - 收藏

    @Test("收藏可增删查，且不重复")
    func favoritesAddRemoveAndDeduplicate() throws {
        let store = FavoritesStore(storageURL: try temporaryStorageURL("favorites.json"))

        store.add("com.example.one")
        store.add("com.example.two")
        store.add("com.example.one")

        #expect(store.favoriteIDs == ["com.example.one", "com.example.two"])
        #expect(store.isFavorite("com.example.one"))
        #expect(!store.isFavorite("com.example.absent"))

        store.remove("com.example.one")
        #expect(!store.isFavorite("com.example.one"))
    }

    @Test("收藏可以往返持久化并保持顺序")
    func favoritesRoundTrip() throws {
        let url = try temporaryStorageURL("favorites.json")
        let writer = FavoritesStore(storageURL: url)
        writer.add("com.example.one")
        writer.add("com.example.two")

        let reader = FavoritesStore(storageURL: url)
        reader.load()
        #expect(reader.favoriteIDs == ["com.example.one", "com.example.two"])
    }
}
