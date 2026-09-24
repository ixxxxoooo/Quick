// FileSearchSettingsTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginFileSearch

// MARK: - 纯逻辑

@Suite("文件搜索谓词")
struct FileSearchPredicateTests {

    @Test("默认只匹配文件名，不碰文件内容")
    func filenameOnlyByDefault() {
        let predicate = FileSearchQuery.predicate(for: "报告", includeContents: false)

        #expect(predicate.format.contains("kMDItemDisplayName"))
        #expect(!predicate.format.contains("kMDItemTextContent"))
        #expect(predicate.arguments == ["报告"])
    }

    @Test("打开内容搜索后连 kMDItemTextContent 一起匹配")
    func contentSearchAddsTheTextContentAttribute() {
        let predicate = FileSearchQuery.predicate(for: "报告", includeContents: true)

        #expect(predicate.format.contains("kMDItemDisplayName"))
        #expect(predicate.format.contains("kMDItemTextContent"))
        // 两个占位符就要两个参数，否则 NSPredicate 会直接抛异常
        #expect(predicate.arguments == ["报告", "报告"])
    }

    @Test("两种谓词不等：开关真的改变了交给 Spotlight 的查询")
    func theSwitchesProduceDifferentPredicates() {
        let filename = FileSearchQuery.predicate(for: "x", includeContents: false)
        let contents = FileSearchQuery.predicate(for: "x", includeContents: true)

        #expect(filename != contents)
    }
}

@Suite("文件搜索的过滤与截断")
struct FileSearchFilteringTests {

    @Test("路径里出现以 . 开头的一段就算隐藏，包括藏在隐藏目录里的文件")
    func hiddenDetectionCoversDotFilesAndDotDirectories() {
        #expect(FileSearchFiltering.isHidden(path: "/Users/x/.zshrc"))
        #expect(FileSearchFiltering.isHidden(path: "/Users/x/.config/quick.json"))
        #expect(FileSearchFiltering.isHidden(path: "/Users/x/notes/.backup/a.txt"))
        #expect(!FileSearchFiltering.isHidden(path: "/Users/x/notes/a.txt"))
        // 名字里带点但不是以点开头
        #expect(!FileSearchFiltering.isHidden(path: "/Users/x/note.backup/a.txt"))
        #expect(!FileSearchFiltering.isHidden(path: "/Users/x/v1.2"))
    }

    @Test("忽略隐藏文件：开与关拿到不同的结果集")
    func ignoreHiddenDropsHiddenEntries() {
        let paths = [
            "/Users/x/report.pdf",
            "/Users/x/.hidden.pdf",
            "/Users/x/.config/stash.pdf"
        ]

        let kept = FileSearchFiltering.applying(
            ignoringHidden: true, limit: 50, to: paths, path: { $0 })
        let all = FileSearchFiltering.applying(
            ignoringHidden: false, limit: 50, to: paths, path: { $0 })

        #expect(kept == ["/Users/x/report.pdf"])
        #expect(all == paths)
        #expect(kept != all)
    }

    @Test("结果上限：20 与 200 拿到不同条数")
    func maxResultsTruncates() {
        let paths = (1...100).map { "/Users/x/file\($0).txt" }

        let twenty = FileSearchFiltering.applying(
            ignoringHidden: true, limit: 20, to: paths, path: { $0 })
        let twoHundred = FileSearchFiltering.applying(
            ignoringHidden: true, limit: 200, to: paths, path: { $0 })

        #expect(twenty.count == 20)
        #expect(twoHundred.count == 100)
        // 截断保留原顺序
        #expect(twenty == Array(paths.prefix(20)))
    }
}

@Suite("文件搜索偏好读取")
struct FileSearchPreferencesTests {

    /// 独立 suite：读映射的用例不碰真实偏好
    private static func scratchDefaults() -> UserDefaults? {
        UserDefaults(suiteName: "com.ixxxxoooo.quick.tests.filesearch.\(UUID().uuidString)")
    }

    @Test("上限只认设置页给出的四档，其余一律回落到 50")
    func maxResultsMapping() {
        for choice in FileSearchPreferences.resultChoices {
            #expect(FileSearchPreferences.maxResults(storedValue: choice) == choice)
        }
        // 没写过（integer(forKey:) 返回 0）与手改坏的值
        #expect(FileSearchPreferences.maxResults(storedValue: 0) == 50)
        #expect(FileSearchPreferences.maxResults(storedValue: 7) == 50)
        #expect(FileSearchPreferences.maxResults(storedValue: -20) == 50)
    }

    @Test("未设置过时就是设置页显示的档位：50 条 + 忽略隐藏 + 不搜内容")
    func emptyDefaultsFallBackToThePaneDefaults() throws {
        let defaults = try #require(Self.scratchDefaults())

        #expect(
            FileSearchPreferences.current(defaults: defaults)
                == FileSearchSettings(maxResults: 50, ignoreHidden: true, includeContents: false))
    }

    @Test("三项设置都跟着键走")
    func settingsFollowStoredValues() throws {
        let defaults = try #require(Self.scratchDefaults())

        defaults.set(200, forKey: PluginSettingKey.FileSearch.maxResults)
        defaults.set(false, forKey: PluginSettingKey.FileSearch.ignoreHidden)
        defaults.set(true, forKey: PluginSettingKey.FileSearch.includeContents)
        #expect(
            FileSearchPreferences.current(defaults: defaults)
                == FileSearchSettings(maxResults: 200, ignoreHidden: false, includeContents: true))

        defaults.set(20, forKey: PluginSettingKey.FileSearch.maxResults)
        defaults.set(true, forKey: PluginSettingKey.FileSearch.ignoreHidden)
        defaults.set(false, forKey: PluginSettingKey.FileSearch.includeContents)
        #expect(
            FileSearchPreferences.current(defaults: defaults)
                == FileSearchSettings(maxResults: 20, ignoreHidden: true, includeContents: false))
    }

    @Test("会话把设置里的三项透出来")
    @MainActor
    func sessionExposesTheConfiguredSettings() throws {
        let defaults = try #require(Self.scratchDefaults())
        let session = FileSearchSession(defaults: defaults)

        #expect(
            session.configuredSettings
                == FileSearchSettings(maxResults: 50, ignoreHidden: true, includeContents: false))

        defaults.set(200, forKey: PluginSettingKey.FileSearch.maxResults)
        defaults.set(false, forKey: PluginSettingKey.FileSearch.ignoreHidden)
        defaults.set(true, forKey: PluginSettingKey.FileSearch.includeContents)
        #expect(
            session.configuredSettings
                == FileSearchSettings(maxResults: 200, ignoreHidden: false, includeContents: true))
    }
}

// MARK: - 插件接线

/// 插件读的是标准偏好存储，用例也只能写标准存储 —— 换成独立 suite 就测不到接线了。
/// 标准存储是进程共享的，所以用例串行并自己收尾。
@MainActor
@Suite("文件搜索插件的设置接线", .serialized)
struct FileSearchPluginSettingsTests {

    private static let touchedKeys = [
        PluginSettingKey.FileSearch.maxResults,
        PluginSettingKey.FileSearch.ignoreHidden,
        PluginSettingKey.FileSearch.includeContents
    ]

    /// 跑完把这三个键的旧值原样放回去，不让用例互相污染，也不留在真实偏好里
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

    /// 造一批假结果，形状与会话从 Spotlight 读回来的完全一致
    private static func fakeResults(_ paths: [String]) -> [FileSearchSession.FileResult] {
        paths.map { path in
            FileSearchSession.FileResult(
                id: path,
                name: (path as NSString).lastPathComponent,
                path: path,
                icon: "doc",
                size: 0,
                modifiedDate: nil
            )
        }
    }

    @Test("结果项映射不再二次截断：设置给多少条就吐多少条")
    func itemMappingDoesNotTruncateAgain() {
        let files = Self.fakeResults((1...100).map { "/Users/x/file\($0).txt" })

        // 以前这里写死 prefix(10)，设置页里的 20/50/100/200 全被压成 10 条
        #expect(FileSearchPlugin.items(for: files).count == 100)
        #expect(FileSearchPlugin.items(for: []).isEmpty)
    }

    @Test("插件持有的会话读的是标准偏好里的设置")
    func pluginSessionReadsTheStandardDefaults() async throws {
        try await Self.withStandardDefaults {
            let plugin = FileSearchPlugin()

            UserDefaults.standard.set(200, forKey: PluginSettingKey.FileSearch.maxResults)
            UserDefaults.standard.set(false, forKey: PluginSettingKey.FileSearch.ignoreHidden)
            UserDefaults.standard.set(true, forKey: PluginSettingKey.FileSearch.includeContents)
            #expect(
                plugin.searchSession.configuredSettings
                    == FileSearchSettings(maxResults: 200, ignoreHidden: false, includeContents: true))

            UserDefaults.standard.set(20, forKey: PluginSettingKey.FileSearch.maxResults)
            UserDefaults.standard.set(true, forKey: PluginSettingKey.FileSearch.ignoreHidden)
            UserDefaults.standard.set(false, forKey: PluginSettingKey.FileSearch.includeContents)
            #expect(
                plugin.searchSession.configuredSettings
                    == FileSearchSettings(maxResults: 20, ignoreHidden: true, includeContents: false))
        }
    }
}
