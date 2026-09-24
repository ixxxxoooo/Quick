// FileSearchTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import QuickPlatform

// MARK: - 触发词

@Suite("文件搜索触发词解析")
struct FileSearchQueryTests {

    @Test("三个前缀都能剥掉")
    func everyPrefixIsStripped() {
        #expect(FileSearchQuery.keyword(in: "f report.pdf") == "report.pdf")
        #expect(FileSearchQuery.keyword(in: "file report.pdf") == "report.pdf")
        #expect(FileSearchQuery.keyword(in: "文件 报告.pdf") == "报告.pdf")
    }

    @Test("前缀大小写不敏感，关键词大小写原样保留")
    func prefixIsCaseInsensitiveButKeywordIsNot() {
        #expect(FileSearchQuery.keyword(in: "FILE Report.PDF") == "Report.PDF")
        #expect(FileSearchQuery.keyword(in: "File x") == "x")
    }

    @Test("file 不会被更短的 f 抢走")
    func longestPrefixWins() {
        // "file x" 的第 2 个字符是 i，不满足 "f "；只有 "file " 能命中
        #expect(FileSearchQuery.keyword(in: "file x") == "x")
        #expect(FileSearchQuery.keyword(in: "f ile x") == "ile x")
    }

    @Test("只打触发词（关键词为空）返回 nil")
    func bareTriggerYieldsNothing() {
        #expect(FileSearchQuery.keyword(in: "f") == nil)
        #expect(FileSearchQuery.keyword(in: "file") == nil)
        #expect(FileSearchQuery.keyword(in: "文件") == nil)
        #expect(FileSearchQuery.keyword(in: "f ") == nil)
        #expect(FileSearchQuery.keyword(in: "file ") == nil)
        #expect(FileSearchQuery.keyword(in: "文件 ") == nil)
    }

    @Test("前缀必须带空格，且必须在开头")
    func prefixNeedsTrailingSpaceAtTheStart() {
        #expect(FileSearchQuery.keyword(in: "fx a") == nil)
        #expect(FileSearchQuery.keyword(in: "文件报告") == nil)
        #expect(FileSearchQuery.keyword(in: " f a") == nil, "前导空白不匹配")
        #expect(FileSearchQuery.keyword(in: "") == nil)
        #expect(FileSearchQuery.keyword(in: "报告.pdf") == nil)
    }

    @Test("纯空白的关键词不会被当成空")
    func whitespaceOnlyKeywordSurvives() {
        // "f  " 剥掉 "f " 之后还剩一个空格，非空 → 会被当成关键词丢给 Spotlight
        #expect(FileSearchQuery.keyword(in: "f  ") == " ")
    }

    @Test("前缀列表非空且无重复")
    func prefixesAreWellFormed() {
        #expect(!FileSearchQuery.prefixes.isEmpty)
        #expect(FileSearchQuery.prefixes.allSatisfy { !$0.isEmpty })
        #expect(Set(FileSearchQuery.prefixes).count == FileSearchQuery.prefixes.count)
    }
}

// MARK: - 谓词

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

// MARK: - 过滤与截断

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

// MARK: - 偏好

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

        defaults.set(200, forKey: SettingsKey.fileSearchMaxResults)
        defaults.set(false, forKey: SettingsKey.fileSearchIgnoreHidden)
        defaults.set(true, forKey: SettingsKey.fileSearchIncludeContents)
        #expect(
            FileSearchPreferences.current(defaults: defaults)
                == FileSearchSettings(maxResults: 200, ignoreHidden: false, includeContents: true))

        defaults.set(20, forKey: SettingsKey.fileSearchMaxResults)
        defaults.set(true, forKey: SettingsKey.fileSearchIgnoreHidden)
        defaults.set(false, forKey: SettingsKey.fileSearchIncludeContents)
        #expect(
            FileSearchPreferences.current(defaults: defaults)
                == FileSearchSettings(maxResults: 20, ignoreHidden: true, includeContents: false))
    }

    @Test("服务把设置里的三项透出来")
    @MainActor
    func serviceExposesTheConfiguredSettings() throws {
        let defaults = try #require(Self.scratchDefaults())
        let service = FileSearchService(defaults: defaults)

        #expect(
            service.configuredSettings
                == FileSearchSettings(maxResults: 50, ignoreHidden: true, includeContents: false))

        defaults.set(200, forKey: SettingsKey.fileSearchMaxResults)
        defaults.set(false, forKey: SettingsKey.fileSearchIgnoreHidden)
        defaults.set(true, forKey: SettingsKey.fileSearchIncludeContents)
        #expect(
            service.configuredSettings
                == FileSearchSettings(maxResults: 200, ignoreHidden: false, includeContents: true))
    }
}

// MARK: - 图标

@Suite("文件图标映射")
struct FileIconMapperTests {

    @Test("文档类")
    func documentExtensions() {
        #expect(FileIconMapper.icon(forFileName: "report.pdf") == "doc.richtext")
        #expect(FileIconMapper.icon(forFileName: "readme.md") == "doc.text")
        #expect(FileIconMapper.icon(forFileName: "notes.txt") == "doc.text")
    }

    @Test("媒体类")
    func mediaExtensions() {
        for name in ["a.jpg", "b.jpeg", "c.png", "d.gif", "e.webp", "f.heic"] {
            #expect(FileIconMapper.icon(forFileName: name) == "photo", "\(name) 应是图片")
        }
        for name in ["a.mp4", "b.mov", "c.avi"] {
            #expect(FileIconMapper.icon(forFileName: name) == "film", "\(name) 应是视频")
        }
        for name in ["a.mp3", "b.wav", "c.aac", "d.m4a"] {
            #expect(FileIconMapper.icon(forFileName: name) == "music.note", "\(name) 应是音频")
        }
    }

    @Test("压缩包与代码")
    func archiveAndCodeExtensions() {
        for name in ["a.zip", "b.rar", "c.7z", "d.tar", "e.gz"] {
            #expect(FileIconMapper.icon(forFileName: name) == "archivebox", "\(name) 应是压缩包")
        }
        for name in ["a.swift", "b.py", "c.js", "d.ts", "e.java", "f.c", "g.cpp", "h.rs"] {
            #expect(
                FileIconMapper.icon(forFileName: name) == "chevron.left.forwardslash.chevron.right",
                "\(name) 应是代码"
            )
        }
        #expect(FileIconMapper.icon(forFileName: "index.html") == "globe")
        #expect(FileIconMapper.icon(forFileName: "style.css") == "globe")
    }

    @Test("扩展名大小写不敏感")
    func extensionIsCaseInsensitive() {
        #expect(FileIconMapper.icon(forFileName: "REPORT.PDF") == "doc.richtext")
        #expect(FileIconMapper.icon(forFileName: "Photo.JPG") == "photo")
        #expect(FileIconMapper.icon(forFileName: "archive.TAR.GZ") == "archivebox")
    }

    @Test("取最后一个扩展名")
    func usesLastExtension() {
        #expect(FileIconMapper.icon(forFileName: "backup.tar.gz") == "archivebox")
        #expect(FileIconMapper.icon(forFileName: "backup.pdf.txt") == "doc.text")
    }

    @Test("没有扩展名、空名与未知扩展名都落到默认图标")
    func unknownFallsBackToDefaultIcon() {
        #expect(FileIconMapper.icon(forFileName: "noextension") == "doc")
        #expect(FileIconMapper.icon(forFileName: "") == "doc")
        #expect(FileIconMapper.icon(forFileName: "report.") == "doc")
        #expect(FileIconMapper.icon(forFileName: "installer.dmg") == "doc")
        // 点开头的隐藏文件在 Foundation 看来没有扩展名
        #expect(FileIconMapper.icon(forFileName: ".gitignore") == "doc")
    }

    @Test("中文与空格文件名不影响判定")
    func unicodeNamesWork() {
        #expect(FileIconMapper.icon(forFileName: "季度报告.pdf") == "doc.richtext")
        #expect(FileIconMapper.icon(forFileName: "my report v2.md") == "doc.text")
    }
}
