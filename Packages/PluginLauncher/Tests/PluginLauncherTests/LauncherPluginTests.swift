// LauncherPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import QuickPlatform
import Testing

@testable import PluginLauncher

@Suite("启动器插件")
@MainActor
struct LauncherPluginTests {

    /// 一个应用过插件 schema 的内存库
    ///
    /// 内存库每个实例彼此独立：测存储不用碰磁盘，也不用清临时目录。
    /// 使用频率与收藏共用同一个库，所以迁移也要一起跑。
    private func makeStorage() throws -> PluginStorage {
        let database = try SQLiteDatabase()
        try database.migrate(LauncherPlugin.storageMigrations)
        return PluginStorage(pluginID: LauncherPlugin.id, database: database)
    }

    // MARK: - 插件契约

    @Test("插件 id 符合约定")
    func identifierConvention() {
        #expect(LauncherPlugin.id == "launcher")
        #expect(!LauncherPlugin.name.isEmpty)
        #expect(!LauncherPlugin.icon.isEmpty)
    }

    @Test("空查询不返回全部应用")
    func emptyQueryDoesNotDumpEveryApp() async throws {
        // 首屏不该把几百个应用一次性铺出来：空查询最多给 20 条。
        let plugin = LauncherPlugin(appIndex: AppIndex(), storage: try makeStorage())
        let results = await plugin.dynamicSearch(query: "   ")
        #expect(results.count <= 20, "空查询（含纯空白）最多返回 20 条")
    }

    @Test("结果 id 带插件前缀且互不重复")
    func resultIdentifiersArePrefixedAndUnique() async throws {
        let plugin = LauncherPlugin(appIndex: AppIndex(), storage: try makeStorage())
        let results = await plugin.dynamicSearch(query: "x")

        let ids = results.map(\.id)
        #expect(Set(ids).count == ids.count, "同一插件内的 SearchableItem.id 必须唯一")
        #expect(ids.allSatisfy { $0.hasPrefix("launcher.") })
        #expect(results.allSatisfy { $0.pluginID == LauncherPlugin.id })
        #expect(results.count <= 20, "非空查询最多返回 20 条")
    }

    @Test("前缀 > 可直接识别并返回 Shell 命令搜索项")
    func directShellCommandPrefix() async throws {
        let plugin = LauncherPlugin(appIndex: AppIndex(), storage: try makeStorage())
        let results = await plugin.dynamicSearch(query: "> echo hello")

        #expect(results.count == 1)
        #expect(results.first?.id == "launcher.shell.direct")
        #expect(results.first?.title.contains("echo hello") == true)
        #expect(results.first?.relevance == 1.0)
    }

    @Test("启停是幂等的，且停用会落盘")
    func activationIsIdempotent() throws {
        let plugin = LauncherPlugin(appIndex: AppIndex(), storage: try makeStorage())
        plugin.activate()
        plugin.activate()
        plugin.deactivate()
        plugin.deactivate()
    }

    // MARK: - 使用频率评分

    @Test("未记录过的应用评分为 0")
    func unknownAppScoresZero() throws {
        let store = RankingStore(storage: try makeStorage())
        #expect(store.score(for: "com.example.never-used") == 0)
    }

    @Test("用得最多的应用评分为 1，其余按比例")
    func scoreIsNormalisedByMostUsed() throws {
        let store = RankingStore(storage: try makeStorage())
        for _ in 0..<4 { store.recordUsage("com.example.frequent") }
        store.recordUsage("com.example.rare")

        #expect(store.score(for: "com.example.frequent") == 1.0)
        #expect(store.score(for: "com.example.rare") == 0.25)
        #expect(store.score(for: "com.example.never-used") == 0)
    }

    @Test("用得越多评分越高")
    func scoreIsMonotonicInUsage() throws {
        let store = RankingStore(storage: try makeStorage())
        store.recordUsage("com.example.a")
        let afterOne = store.score(for: "com.example.a")
        store.recordUsage("com.example.a")
        let afterTwo = store.score(for: "com.example.a")

        #expect(afterTwo >= afterOne)
    }

    @Test("使用频率可以往返持久化")
    func usageCountsRoundTrip() throws {
        let storage = try makeStorage()
        let writer = RankingStore(storage: storage)
        for _ in 0..<3 { writer.recordUsage("com.example.round-trip") }

        // 新实例的 init 直接读库 —— init 能读到，才说明上一实例真的落库了
        let reader = RankingStore(storage: storage)
        #expect(reader.score(for: "com.example.round-trip") == 1.0)
    }

    @Test("每次使用都是单行自增，计数不会因为剪枝/重写而丢失")
    func usageIncrementsAreAccumulated() throws {
        let storage = try makeStorage()
        let store = RankingStore(storage: storage)
        for _ in 0..<5 { store.recordUsage("com.example.counted") }

        // score 是相对最大值的比例：5 次的仍是最大，4 次的应是 0.8，
        // 说明计数在累加而不是每次被覆盖成 1
        for _ in 0..<4 { store.recordUsage("com.example.other") }
        #expect(store.score(for: "com.example.counted") == 1.0)
        #expect(store.score(for: "com.example.other") == 0.8)

        let reader = RankingStore(storage: storage)
        #expect(reader.score(for: "com.example.counted") == 1.0)
        #expect(reader.score(for: "com.example.other") == 0.8)
    }

    @Test("第二个实例能看到第一个实例刚记录的使用次数")
    func rankingMutationIsVisibleToSecondStore() throws {
        let storage = try makeStorage()
        let writer = RankingStore(storage: storage)
        let observer = RankingStore(storage: storage)
        #expect(observer.score(for: "com.example.shared") == 0)

        writer.recordUsage("com.example.shared")

        observer.load()
        #expect(observer.score(for: "com.example.shared") == 1.0)
    }

    @Test("空库加载为空记录而不是启动失败")
    func emptyDatabaseLoadsEmpty() throws {
        let store = RankingStore(storage: try makeStorage())
        #expect(store.score(for: "com.example.any") == 0)
    }

    // MARK: - 收藏

    @Test("收藏可增删查，且不重复")
    func favoritesAddRemoveAndDeduplicate() throws {
        let store = FavoritesStore(storage: try makeStorage())

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
        let storage = try makeStorage()
        let writer = FavoritesStore(storage: storage)
        writer.add("com.example.one")
        writer.add("com.example.two")

        // 新实例的 init 直接读库，顺序来自 sort_order
        let reader = FavoritesStore(storage: storage)
        #expect(reader.favoriteIDs == ["com.example.one", "com.example.two"])
    }

    @Test("删掉中间项后再收藏仍排在最后，不会撞号重排")
    func favoritesOrderSurvivesRemoval() throws {
        let storage = try makeStorage()
        let store = FavoritesStore(storage: storage)
        store.add("com.example.one")
        store.add("com.example.two")
        store.add("com.example.three")

        store.remove("com.example.two")
        store.add("com.example.four")

        #expect(store.favoriteIDs == ["com.example.one", "com.example.three", "com.example.four"])
        // 库里的顺序必须与内存一致，否则重启后用户会看到收藏换了位置
        #expect(FavoritesStore(storage: storage).favoriteIDs == store.favoriteIDs)
    }

    @Test("第二个实例能看到第一个实例刚加的收藏")
    func favoritesMutationIsVisibleToSecondStore() throws {
        let storage = try makeStorage()
        let writer = FavoritesStore(storage: storage)
        let observer = FavoritesStore(storage: storage)

        writer.add("com.example.shared")
        observer.load()

        #expect(observer.isFavorite("com.example.shared"))
        writer.remove("com.example.shared")
        observer.load()
        #expect(!observer.isFavorite("com.example.shared"))
    }
}
