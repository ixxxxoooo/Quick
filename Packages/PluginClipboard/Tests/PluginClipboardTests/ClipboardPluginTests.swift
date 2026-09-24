// ClipboardPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginClipboard

@Suite("剪贴板插件")
@MainActor
struct ClipboardPluginTests {

    /// 造一个跑过插件迁移的内存库
    ///
    /// 内存库每个实例互相独立，所以测试之间不会串数据，也不用清临时目录。
    private func makeDatabase() throws -> SQLiteDatabase {
        let database = try SQLiteDatabase()
        try database.migrate(ClipboardPlugin.storageMigrations)
        return database
    }

    private func makeStore(database: SQLiteDatabase? = nil) throws -> ClipboardStore {
        let database = try database ?? makeDatabase()
        return ClipboardStore(storage: PluginStorage(pluginID: ClipboardPlugin.id, database: database))
    }

    // MARK: - 插件契约

    @Test("插件 id 符合约定")
    func identifierConvention() {
        #expect(ClipboardPlugin.id == "clipboard")
        #expect(!ClipboardPlugin.name.isEmpty)
        #expect(!ClipboardPlugin.icon.isEmpty)
    }

    @Test("插件声明了自己的 schema")
    func pluginDeclaresItsSchema() {
        let ids = ClipboardPlugin.storageMigrations.map(\.id)
        #expect(ids == ["clipboard.history", "clipboard.history.source"])
    }

    @Test("启停是幂等的")
    func activationIsIdempotent() throws {
        let plugin = ClipboardPlugin(
            storage: PluginStorage(pluginID: ClipboardPlugin.id, database: try makeDatabase()))
        plugin.activate()
        plugin.activate()
        plugin.deactivate()
        plugin.deactivate()
    }

    // MARK: - 条目预览

    @Test("预览会压平换行并去掉首尾空白")
    func previewFlattensNewlines() {
        let entry = ClipboardEntry(text: "  第一行\n第二行\r\n第三行  ")
        #expect(entry.preview == "第一行 第二行 第三行")
    }

    @Test("超长文本预览截断到 80 字符并加省略号")
    func previewTruncatesLongText() {
        let entry = ClipboardEntry(text: String(repeating: "a", count: 200))
        #expect(entry.preview.count == 81, "80 个字符 + 1 个省略号")
        #expect(entry.preview.hasSuffix("…"))
    }

    @Test("刚好 80 字符不截断")
    func previewKeepsExactlyEightyCharacters() {
        let entry = ClipboardEntry(text: String(repeating: "a", count: 80))
        #expect(entry.preview.count == 80)
        #expect(!entry.preview.hasSuffix("…"))
    }

    @Test("每种内容类型都有图标")
    func everyContentTypeHasAnIcon() {
        for type in [
            ClipboardEntry.ContentType.text, .url, .code, .color
        ] {
            #expect(!type.icon.isEmpty, "\(type.rawValue) 缺少图标")
        }
    }

    // MARK: - 存储

    @Test("相同内容不重复记录，且新的排在最前")
    func addDeduplicatesByText() throws {
        let store = try makeStore()

        let first = ClipboardEntry(text: "同一段内容")
        store.add(first)
        let second = ClipboardEntry(text: "同一段内容")
        store.add(second)

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.id == second.id)
    }

    @Test("图片按数据内容去重")
    func addDeduplicatesImagesByData() throws {
        let store = try makeStore()
        let data = Data(repeating: 0x42, count: 128)

        store.add(ClipboardEntry(imageData: data, sizeDescription: "8×8"))
        store.add(ClipboardEntry(imageData: data, sizeDescription: "8×8"))

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.imageData == data)
    }

    @Test("去重发生在数据库里，不只是内存里")
    func deduplicationPersists() throws {
        let database = try makeDatabase()
        let store = try makeStore(database: database)
        store.add(ClipboardEntry(text: "重复"))
        store.add(ClipboardEntry(text: "重复"))

        // 直接问数据库：内存里只剩一条不算数，表里也必须只有一条
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM clipboard_history") == 1)
    }

    @Test("清空历史会保留收藏")
    func clearHistoryKeepsFavorites() throws {
        let store = try makeStore()

        let kept = ClipboardEntry(text: "要保留的")
        store.add(kept)
        store.add(ClipboardEntry(text: "要清掉的"))
        store.toggleFavorite(kept.id)

        store.clearHistory()

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.text == "要保留的")
        #expect(store.entries.first?.isFavorite == true)
    }

    @Test("搜索忽略大小写，空查询返回全部")
    func searchIsCaseInsensitive() throws {
        let store = try makeStore()
        store.add(ClipboardEntry(text: "Hello World"))
        store.add(ClipboardEntry(text: "别的内容"))

        #expect(store.search("").count == 2)
        #expect(store.search("hello").count == 1)
        #expect(store.search("HELLO").count == 1)
        #expect(store.search("不存在的关键词").isEmpty)
    }

    @Test("删除按 id 生效，并且真的从库里删掉")
    func removeById() throws {
        let database = try makeDatabase()
        let store = try makeStore(database: database)
        let entry = ClipboardEntry(text: "待删除")
        store.add(entry)
        store.add(ClipboardEntry(text: "保留"))

        store.remove(entry.id)

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.text == "保留")
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM clipboard_history") == 1)
    }

    @Test("置顶与收藏状态能改回数据库")
    func flagsArePersisted() throws {
        let database = try makeDatabase()
        let store = try makeStore(database: database)
        let entry = ClipboardEntry(text: "置顶我")
        store.add(entry)

        store.togglePinned(entry.id)
        store.toggleFavorite(entry.id)

        let row = try database.query("SELECT is_pinned, is_favorite FROM clipboard_history").first
        #expect(row?.bool("is_pinned") == true)
        #expect(row?.bool("is_favorite") == true)
    }

    @Test("历史可以往返持久化")
    func historyRoundTrip() throws {
        let database = try makeDatabase()
        let writer = try makeStore(database: database)
        writer.add(ClipboardEntry(text: "往返测试", type: .code))
        writer.save()

        // 同一个库上重新打开一个 store：这就是「重启应用后历史还在」的场景
        let reader = try makeStore(database: database)
        reader.load()

        #expect(reader.entries.count == 1)
        #expect(reader.entries.first?.text == "往返测试")
        #expect(reader.entries.first?.type == .code)
    }

    @Test("图片数据往返不丢字节")
    func imageRoundTrip() throws {
        let database = try makeDatabase()
        let png = Data([0x89, 0x50, 0x4E, 0x47] + Array(repeating: 0xCD, count: 4096))
        let writer = try makeStore(database: database)
        writer.add(ClipboardEntry(imageData: png, sizeDescription: "64×64"))

        let reader = try makeStore(database: database)
        #expect(reader.entries.first?.imageData == png)
        #expect(reader.entries.first?.imageSizeDescription == "64×64")
        #expect(reader.entries.first?.type == .image)
    }

    @Test("图片预览不再带 emoji 或「图片」字样")
    func imagePreviewHasNoEmoji() {
        let entry = ClipboardEntry(imageData: Data([0x01]), sizeDescription: "64×64")
        #expect(entry.preview == "64×64")
        #expect(!entry.preview.contains("📷"))
    }

    @Test("来源应用随条目往返持久化")
    func sourceAppRoundTrip() throws {
        let database = try makeDatabase()
        let writer = try makeStore(database: database)
        writer.add(
            ClipboardEntry(
                text: "来自 Safari 的复制",
                sourceAppName: "Safari",
                sourceBundleID: "com.apple.Safari"
            ))

        let reader = try makeStore(database: database)
        #expect(reader.entries.first?.sourceAppName == "Safari")
        #expect(reader.entries.first?.sourceBundleID == "com.apple.Safari")
    }

    @Test("坏数据只丢那一行，不影响整份历史")
    func corruptRowIsSkipped() throws {
        // 以前是「整个 json 解码失败 → 历史全空」。现在一行坏数据只坏一行。
        let database = try makeDatabase()
        let store = try makeStore(database: database)
        store.add(ClipboardEntry(text: "好数据"))

        try database.execute(
            """
            INSERT INTO clipboard_history (id, text, type, created_at)
            VALUES ('不是 uuid', '坏数据', '未知类型', 0)
            """)

        let reopened = try makeStore(database: database)
        #expect(reopened.entries.count == 1)
        #expect(reopened.entries.first?.text == "好数据")
    }

    @Test("排序是置顶优先，其余按时间倒序")
    func pinnedSortsFirst() throws {
        let store = try makeStore()
        let oldest = ClipboardEntry(text: "最早的")
        store.add(oldest)
        store.add(ClipboardEntry(text: "中间的"))
        store.add(ClipboardEntry(text: "最新的"))

        store.togglePinned(oldest.id)

        #expect(store.entries.first?.text == "最早的")
        #expect(store.entries.first?.isPinned == true)
        #expect(store.entries.map(\.text).dropFirst() == ["最新的", "中间的"])
    }
}

// MARK: - 上限与预算

/// 这一组会改 `UserDefaults`，所以串行执行：`UserDefaults` 是进程级的，
/// 并行跑会让「上限是多少」这件事取决于另一个测试的进度。
@Suite("剪贴板上限与图片预算", .serialized)
@MainActor
struct ClipboardLimitTests {

    private func makeDatabase() throws -> SQLiteDatabase {
        let database = try SQLiteDatabase()
        try database.migrate(ClipboardPlugin.storageMigrations)
        return database
    }

    /// 临时改一个设置键并在结束时还原
    private func withSetting(_ key: String, value: Any, _ body: () throws -> Void) rethrows {
        let original = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(value, forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try body()
    }

    @Test("条数上限来自设置，而不是硬编码")
    func capComesFromSettings() throws {
        try withSetting(PluginSettingKey.Clipboard.maxEntries, value: 3) {
            let store = try! ClipboardStore(
                storage: PluginStorage(pluginID: ClipboardPlugin.id, database: makeDatabase()))
            for index in 0..<10 {
                store.add(ClipboardEntry(text: "条目 \(index)"))
            }

            #expect(store.entries.count == 3)
            // 留下的是最新的三条
            #expect(store.entries.map(\.text) == ["条目 9", "条目 8", "条目 7"])
        }
    }

    @Test("置顶与收藏不参与条数剪枝")
    func pinnedAndFavoritesSurvivePruning() throws {
        try withSetting(PluginSettingKey.Clipboard.maxEntries, value: 2) {
            let store = try! ClipboardStore(
                storage: PluginStorage(pluginID: ClipboardPlugin.id, database: makeDatabase()))

            let pinned = ClipboardEntry(text: "置顶的")
            store.add(pinned)
            store.togglePinned(pinned.id)

            let favorite = ClipboardEntry(text: "收藏的")
            store.add(favorite)
            store.toggleFavorite(favorite.id)

            for index in 0..<5 {
                store.add(ClipboardEntry(text: "普通 \(index)"))
            }

            let texts = Set(store.entries.map(\.text))
            #expect(texts.contains("置顶的"), "置顶条目不该被剪掉")
            #expect(texts.contains("收藏的"), "收藏条目不该被剪掉")
            // 普通条目只剩上限允许的两条
            #expect(store.entries.filter { !$0.isPinned && !$0.isFavorite }.count == 2)
        }
    }

    @Test("图片超出字节预算时按最旧优先剪枝，置顶的图片保留")
    func imageBudgetPrunesOldestFirst() throws {
        // 预算 1000 字节，每条图片 400 字节 → 只放得下两条
        try withSetting(PluginSettingKey.Clipboard.imageByteBudget, value: 1000) {
            let store = try! ClipboardStore(
                storage: PluginStorage(pluginID: ClipboardPlugin.id, database: makeDatabase()))

            let pinnedImage = ClipboardEntry(
                imageData: Data(repeating: 0x01, count: 400), sizeDescription: "1×1")
            store.add(pinnedImage)
            store.togglePinned(pinnedImage.id)

            for index in 0..<4 {
                store.add(
                    ClipboardEntry(
                        imageData: Data(repeating: UInt8(index + 2), count: 400),
                        sizeDescription: "2×2"))
            }

            let images = store.entries.filter { $0.type == .image }
            #expect(images.contains { $0.isPinned }, "置顶的图片必须留下")

            let total = images.compactMap(\.imageData).reduce(0) { $0 + $1.count }
            // 置顶的 400 字节不受预算约束，普通图片要压到预算以内
            let unpinned = images.filter { !$0.isPinned }.compactMap(\.imageData).reduce(0) { $0 + $1.count }
            #expect(unpinned <= 1000, "普通图片总字节 \(unpinned) 应压到预算内（含置顶共 \(total)）")
        }
    }

    @Test("没有设置时用默认上限")
    func fallsBackToDefaults() throws {
        UserDefaults.standard.removeObject(forKey: PluginSettingKey.Clipboard.maxEntries)
        let store = try ClipboardStore(
            storage: PluginStorage(pluginID: ClipboardPlugin.id, database: makeDatabase()))
        for index in 0..<505 {
            store.add(ClipboardEntry(text: "条目 \(index)"))
        }
        #expect(store.entries.count == 500)
    }
}

// MARK: - 设置接线

/// 这一组验证设置页上的开关真的改变了行为，而不是只把值写进 `UserDefaults`。
///
/// 串行执行的理由和上面那组一样：`UserDefaults` 是进程级的，并行跑会让
/// 「开关是开还是关」取决于另一个测试的进度。
@Suite("剪贴板设置接线", .serialized)
@MainActor
struct ClipboardSettingWiringTests {

    private func makeDatabase() throws -> SQLiteDatabase {
        let database = try SQLiteDatabase()
        try database.migrate(ClipboardPlugin.storageMigrations)
        return database
    }

    private func makeStore(database: SQLiteDatabase) -> ClipboardStore {
        ClipboardStore(storage: PluginStorage(pluginID: ClipboardPlugin.id, database: database))
    }

    private func makePlugin(database: SQLiteDatabase) -> ClipboardPlugin {
        ClipboardPlugin(storage: PluginStorage(pluginID: ClipboardPlugin.id, database: database))
    }

    /// 临时改一个设置键并在结束时还原
    private func withSetting(
        _ key: String, value: Any, _ body: () async throws -> Void
    ) async rethrows {
        let original = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(value, forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try await body()
    }

    /// 让出一次主 actor，等设置变化的通知投递落地
    ///
    /// 观察者是在 main 队列上被回调的，写入之后不保证在同一行代码里就送达。
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    /// 搜索结果里除「打开剪贴板管理器」之外的那几条
    private func entryItems(in database: SQLiteDatabase) async -> [SearchableItem] {
        let items = await makePlugin(database: database).dynamicSearch(query: "剪贴板")
        return items.filter { $0.id != "clipboard.open-panel" }
    }

    @Test("开关关着时激活不启动监听，开着时启动")
    func activationFollowsTheMonitorSetting() async throws {
        try await withSetting(PluginSettingKey.Clipboard.monitorEnabled, value: false) {
            let plugin = makePlugin(database: try makeDatabase())
            plugin.activate()
            #expect(plugin.isMonitoring == false, "开关关着却启动了监听")
            plugin.deactivate()
        }

        try await withSetting(PluginSettingKey.Clipboard.monitorEnabled, value: true) {
            let plugin = makePlugin(database: try makeDatabase())
            plugin.activate()
            #expect(plugin.isMonitoring, "开关开着却没有启动监听")
            plugin.deactivate()
        }

        // 没设置过 = 用户没动过，按设置页上的默认值（开）处理
        UserDefaults.standard.removeObject(forKey: PluginSettingKey.Clipboard.monitorEnabled)
        let plugin = makePlugin(database: try makeDatabase())
        plugin.activate()
        #expect(plugin.isMonitoring, "没有设置过时应当默认开启监听")
        plugin.deactivate()
    }

    @Test("运行期关掉开关会停掉监听，再打开会重新启动")
    func togglingTheMonitorSettingWhileActive() async throws {
        let plugin = makePlugin(database: try makeDatabase())
        plugin.activate()
        #expect(plugin.isMonitoring)

        await withSetting(PluginSettingKey.Clipboard.monitorEnabled, value: false) {
            await settle()
            #expect(plugin.isMonitoring == false, "开关关掉后监听器还在跑")

            // 用户又把开关打开：不必重启应用，监听要自己回来
            UserDefaults.standard.set(true, forKey: PluginSettingKey.Clipboard.monitorEnabled)
            await settle()
            #expect(plugin.isMonitoring, "开关重新打开后监听器没有回来")

            // 先摘掉观察者，免得 withSetting 还原键值时又把监听器拉起来
            plugin.deactivate()
        }
    }

    /// 监听器从 `Timer` 换成 `Task` 之后，这里锁住的是两条容易写坏的性质：
    /// 重复 `start()` 不能起第二个轮询（会重置变更计数、丢内容），
    /// `stop()` 之后不能再有轮询碰粘贴板。
    @Test("监听器的启停：start 幂等、stop 真的停")
    func monitorStartIsIdempotentAndStopStops() async {
        let monitor = ClipboardMonitor()

        monitor.start()
        monitor.start()
        #expect(monitor.isRunning, "start 之后应当是运行中")

        monitor.stop()
        #expect(monitor.isRunning == false, "stop 之后应当不再运行")

        // 再跑一轮，确认停掉之后没有残留任务在碰 `NSPasteboard`
        monitor.start()
        #expect(monitor.isRunning)
        monitor.stop()
        #expect(monitor.isRunning == false)
    }

    @Test("退出时清除历史：开关打开才清，且保留收藏")
    func clearOnQuitFollowsTheSetting() async throws {        try await withSetting(PluginSettingKey.Clipboard.clearOnQuit, value: false) {
            let database = try makeDatabase()
            makeStore(database: database).add(ClipboardEntry(text: "不该被清掉的"))

            let plugin = makePlugin(database: database)
            plugin.activate()
            plugin.deactivate()

            #expect(
                try database.scalarInt("SELECT COUNT(*) AS value FROM clipboard_history") == 1,
                "开关关着却清空了历史")
        }

        try await withSetting(PluginSettingKey.Clipboard.clearOnQuit, value: true) {
            let database = try makeDatabase()
            let store = makeStore(database: database)
            let favorite = ClipboardEntry(text: "收藏的")
            store.add(favorite)
            store.add(ClipboardEntry(text: "普通条目"))
            store.toggleFavorite(favorite.id)

            let plugin = makePlugin(database: database)
            plugin.activate()
            plugin.deactivate()

            let remaining = try database.query("SELECT text FROM clipboard_history")
            #expect(remaining.count == 1, "退出时应当清掉普通条目")
            #expect(remaining.first?.text("text") == "收藏的", "收藏条目不该被清掉")
        }
    }

    @Test("关掉预览后搜索结果里不出现剪贴板正文")
    func previewFollowsTheSetting() async throws {
        let database = try makeDatabase()
        makeStore(database: database).add(ClipboardEntry(text: "Hello World"))

        await withSetting(PluginSettingKey.Clipboard.showPreview, value: true) {
            let items = await entryItems(in: database)
            #expect(items.count == 1)
            #expect(items.first?.title.contains("Hello World") == true, "开着预览时标题就该是内容")
        }

        try await withSetting(PluginSettingKey.Clipboard.showPreview, value: false) {
            let items = await entryItems(in: database)
            #expect(items.count == 1, "关掉预览不该把结果一起关掉")

            let item = try #require(items.first)
            #expect(!item.title.contains("Hello World"), "标题里出现了剪贴板正文")
            #expect(item.subtitle?.contains("Hello World") == false, "副标题里出现了剪贴板正文")
            #expect(item.title == ClipboardEntry.ContentType.text.displayName, "标题应当退化成内容类型")
            #expect(item.subtitle?.contains("文本") == true, "副标题要有内容类型，不能只剩时间戳")
        }
    }

    @Test("关掉去重后相同内容各留一条")
    func deduplicationFollowsTheSetting() async throws {
        try await withSetting(PluginSettingKey.Clipboard.deduplication, value: true) {
            let database = try makeDatabase()
            let store = makeStore(database: database)
            store.add(ClipboardEntry(text: "重复"))
            store.add(ClipboardEntry(text: "重复"))

            #expect(store.entries.count == 1, "开着去重时不该留下两条")
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM clipboard_history") == 1)
        }

        try await withSetting(PluginSettingKey.Clipboard.deduplication, value: false) {
            let database = try makeDatabase()
            let store = makeStore(database: database)
            store.add(ClipboardEntry(text: "重复"))
            store.add(ClipboardEntry(text: "重复"))

            #expect(store.entries.count == 2, "关掉去重后两条都要留下")
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM clipboard_history") == 2)
        }
    }
}
