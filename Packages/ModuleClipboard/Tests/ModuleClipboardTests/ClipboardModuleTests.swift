// ClipboardModuleTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import ModuleClipboard

@Suite("剪贴板模块")
@MainActor
struct ClipboardModuleTests {

    /// 临时存储路径
    ///
    /// 目录要真正建出来：生产环境里 `AppPaths.moduleData(_:)` 会创建目录，
    /// 这里必须模拟同样的前提，否则测的是「目录不存在」而不是存储本身。
    private func temporaryStorageURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("history.json")
    }

    // MARK: - 模块契约

    @Test("模块 id 符合约定")
    func identifierConvention() {
        #expect(ClipboardModule.id == "clipboard")
        #expect(!ClipboardModule.name.isEmpty)
        #expect(!ClipboardModule.icon.isEmpty)
    }

    @Test("启停是幂等的")
    func activationIsIdempotent() {
        let module = ClipboardModule()
        module.activate()
        module.activate()
        module.deactivate()
        module.deactivate()
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
        let store = ClipboardStore(storageURL: try temporaryStorageURL())

        let first = ClipboardEntry(text: "同一段内容")
        store.add(first)
        let second = ClipboardEntry(text: "同一段内容")
        store.add(second)

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.id == second.id)
    }

    @Test("历史条数被限制在上限内")
    func historyIsCapped() throws {
        let store = ClipboardStore(storageURL: try temporaryStorageURL())
        for index in 0..<505 {
            store.add(ClipboardEntry(text: "条目 \(index)"))
        }
        #expect(store.entries.count == 500)
    }

    @Test("清空历史会保留收藏")
    func clearHistoryKeepsFavorites() throws {
        let store = ClipboardStore(storageURL: try temporaryStorageURL())

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
        let store = ClipboardStore(storageURL: try temporaryStorageURL())
        store.add(ClipboardEntry(text: "Hello World"))
        store.add(ClipboardEntry(text: "别的内容"))

        #expect(store.search("").count == 2)
        #expect(store.search("hello").count == 1)
        #expect(store.search("HELLO").count == 1)
        #expect(store.search("不存在的关键词").isEmpty)
    }

    @Test("删除按 id 生效")
    func removeById() throws {
        let store = ClipboardStore(storageURL: try temporaryStorageURL())
        let entry = ClipboardEntry(text: "待删除")
        store.add(entry)
        store.add(ClipboardEntry(text: "保留"))

        store.remove(entry.id)

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.text == "保留")
    }

    @Test("历史可以往返持久化")
    func historyRoundTrip() throws {
        let url = try temporaryStorageURL()
        let writer = ClipboardStore(storageURL: url)
        writer.add(ClipboardEntry(text: "往返测试", type: .code))
        writer.save()

        let reader = ClipboardStore(storageURL: url)
        reader.load()

        #expect(reader.entries.count == 1)
        #expect(reader.entries.first?.text == "往返测试")
        #expect(reader.entries.first?.type == .code)
    }

    @Test("损坏的存储文件不会让加载失败")
    func corruptStorageDegradesGracefully() throws {
        let url = try temporaryStorageURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("这不是合法 JSON".utf8).write(to: url)

        let store = ClipboardStore(storageURL: url)
        store.load()
        #expect(store.entries.isEmpty, "损坏数据必须降级为空历史，而不是让模块崩掉")
    }
}
