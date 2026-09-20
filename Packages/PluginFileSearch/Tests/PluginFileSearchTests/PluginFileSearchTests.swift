// PluginFileSearchTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginFileSearch

// MARK: - 纯逻辑

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

// MARK: - 插件契约

@Suite("文件搜索插件契约")
@MainActor
struct FileSearchPluginTests {

    @Test("id 是约定的字面量且为 kebab-case")
    func identifierConvention() {
        #expect(FileSearchPlugin.id == "filesearch")
        #expect(
            FileSearchPlugin.id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" },
            "id 是事件路由与设置存储的主键，必须是 kebab-case，实际为 \(FileSearchPlugin.id)"
        )
    }

    @Test("名称、图标与触发词非空")
    func displayMetadataIsPresent() {
        #expect(!FileSearchPlugin.name.isEmpty)
        #expect(!FileSearchPlugin.icon.isEmpty)
        #expect(!FileSearchPlugin.triggerWords.isEmpty)
    }

    @Test("公开声明的触发词都带得动解析")
    func announcedTriggerWordsAreUsable() {
        for word in FileSearchPlugin.triggerWords {
            #expect(
                FileSearchQuery.keyword(in: "\(word) 报告") != nil,
                "triggerWords 里声明的「\(word)」没有对应的解析前缀，用户按提示输入不会有任何反应"
            )
        }
    }

    @Test("无关查询不返回结果，也不触碰 Spotlight")
    func unrelatedQueryYieldsNothing() async {
        let plugin = FileSearchPlugin()
        let items: [SearchableItem] = await plugin.searchItems(query: "definitely-unrelated")

        #expect(items.isEmpty)
        #expect(await plugin.searchItems(query: "").isEmpty)
    }

    @Test("只打触发词不返回结果")
    func bareTriggerYieldsNothing() async {
        let plugin = FileSearchPlugin()
        #expect(await plugin.searchItems(query: "f").isEmpty)
        #expect(await plugin.searchItems(query: "file").isEmpty)
        #expect(await plugin.searchItems(query: "文件").isEmpty)
        #expect(await plugin.searchItems(query: "f ").isEmpty)
    }

    // searchItems 的正向路径（触发词 + 关键词 → 结果项）要跑 NSMetadataQuery，
    // 那需要 Spotlight 与整机索引，测试里不允许跑。这一段由 FileSearchQuery 与
    // FileIconMapper 的用例覆盖：关键词解析正确、图标映射正确、结果项构造只是把
    // 它们拼进 SearchableItem。
}
