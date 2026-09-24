// SnippetsSettingsTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginSnippets

/// 这一组验证设置页上的两个开关真的改变了行为，而不是只把值写进 `UserDefaults`。
///
/// 插件读的是标准偏好存储，用例也只能写标准存储 —— 换成独立 suite 就测不到接线了。
/// 标准存储是进程共享的，所以用例必须串行并自己收尾（见 `withStandardDefaults`）。
@Suite("片段插件的设置接线", .serialized)
@MainActor
struct SnippetsSettingWiringTests {

    private static let touchedKeys = [
        PluginSettingKey.Snippets.autoExpand,
        PluginSettingKey.Snippets.showSnippetHint
    ]

    /// 跑完把这两个键的旧值原样放回去，不让用例互相污染，也不留在真实偏好里
    private static func withStandardDefaults(_ body: () async throws -> Void) async throws {
        var saved: [String: Any] = [:]
        for key in touchedKeys {
            saved[key] = UserDefaults.standard.object(forKey: key)
        }
        defer {
            for key in touchedKeys {
                if let previous = saved[key] {
                    UserDefaults.standard.set(previous, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        try await body()
    }

    /// 装好 schema 的内存库 + 一个插件，片段先落库
    ///
    /// 插件的 store 是私有的，所以片段只能从同一个库写进去；构造插件必须放在写入之后，
    /// 否则插件的 store 在 init 时读到的还是空库。
    private static func makePlugin(storing snippet: Snippet) throws -> SnippetsPlugin {
        let database = try SQLiteDatabase()
        try database.migrate(SnippetsPlugin.storageMigrations)
        let storage = PluginStorage(pluginID: SnippetsPlugin.id, database: database)
        SnippetStore(storage: storage).add(snippet)
        return SnippetsPlugin(storage: storage)
    }

    @Test("自动展开开关：开着替换模板变量，关掉原样复制")
    func autoExpandFollowsTheSetting() async throws {
        try await Self.withStandardDefaults {
            let plugin = try Self.makePlugin(
                storing: Snippet(title: "签名", content: "你好 {date}", keyword: "sig"))

            var copied: [String] = []
            let subscription = EventBus.shared.on(CopyToClipboardEvent.self) {
                copied.append($0.text)
            }
            defer { subscription.cancel() }

            UserDefaults.standard.set(true, forKey: PluginSettingKey.Snippets.autoExpand)
            let expanding = try #require(await plugin.dynamicSearch(query: "sig").first)
            expanding.action()
            let expanded = try #require(copied.first)
            #expect(
                !expanded.contains("{date}"),
                "开关开着时模板变量应当被替换，实际复制的是 \(expanded)")

            UserDefaults.standard.set(false, forKey: PluginSettingKey.Snippets.autoExpand)
            let raw = try #require(await plugin.dynamicSearch(query: "sig").first)
            raw.action()
            #expect(
                copied.last == "你好 {date}",
                "开关关掉时应当原样复制，实际复制的是 \(copied.last ?? "空")")
        }
    }

    @Test("触发提示开关：关掉后搜索结果不再带关键词")
    func snippetHintFollowsTheSetting() async throws {
        try await Self.withStandardDefaults {
            let plugin = try Self.makePlugin(
                storing: Snippet(title: "签名", content: "内容", keyword: "sig"))

            UserDefaults.standard.set(true, forKey: PluginSettingKey.Snippets.showSnippetHint)
            #expect(await plugin.dynamicSearch(query: "sig").first?.shortcutHint == ":sig")

            UserDefaults.standard.set(false, forKey: PluginSettingKey.Snippets.showSnippetHint)
            #expect(
                await plugin.dynamicSearch(query: "sig").first?.shortcutHint == nil,
                "开关关掉后结果项不该再带触发关键词")
        }
    }

    @Test("两个开关没设置过时都按设置页显示的「开」")
    func unsetSwitchesFallBackToOn() async throws {
        try await Self.withStandardDefaults {
            UserDefaults.standard.removeObject(forKey: PluginSettingKey.Snippets.showSnippetHint)
            UserDefaults.standard.removeObject(forKey: PluginSettingKey.Snippets.autoExpand)

            let plugin = try Self.makePlugin(
                storing: Snippet(title: "签名", content: "你好 {date}", keyword: "sig"))

            var copied: [String] = []
            let subscription = EventBus.shared.on(CopyToClipboardEvent.self) {
                copied.append($0.text)
            }
            defer { subscription.cancel() }

            let item = try #require(await plugin.dynamicSearch(query: "sig").first)
            #expect(item.shortcutHint == ":sig", "没设置过时提示应当按默认的开处理")
            item.action()
            #expect(
                copied.first?.contains("{date}") == false,
                "没设置过时展开应当按默认的开处理，实际复制的是 \(copied.first ?? "空")")
        }
    }
}
