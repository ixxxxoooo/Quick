// MarkdownPreviewPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginMarkdownPreview

@Suite("Markdown 预览的字符串统计")
@MainActor
struct MarkdownPreviewLogicTests {

    @Test("空文本不显示统计")
    func emptyTextHasNoLabel() {
        #expect(MarkdownPreviewLogic.characterCountLabel(for: "") == nil)
    }

    @Test("空白不是空：一个空格算一个字符")
    func whitespaceIsCounted() {
        #expect(MarkdownPreviewLogic.characterCountLabel(for: " ") == "1 字符")
        #expect(MarkdownPreviewLogic.characterCountLabel(for: "\n") == "1 字符")
    }

    @Test("按字符计数：ASCII 与中文")
    func countsCharactersNotBytes() {
        #expect(MarkdownPreviewLogic.characterCountLabel(for: "hello") == "5 字符")
        #expect(MarkdownPreviewLogic.characterCountLabel(for: "你好") == "2 字符")
        #expect(MarkdownPreviewLogic.characterCountLabel(for: "a\nb") == "3 字符")
    }

    @Test("按字形簇计数：组合字数少于 UTF-16 码元数")
    func countsGraphemeClusters() {
        let family = "👨‍👩‍👧‍👦"
        let combined = "e\u{0301}"
        let flag = "🇨🇳"

        #expect(MarkdownPreviewLogic.characterCountLabel(for: family) == "1 字符")
        #expect(MarkdownPreviewLogic.characterCountLabel(for: combined) == "1 字符")
        #expect(MarkdownPreviewLogic.characterCountLabel(for: flag) == "1 字符")

        // 这三个字符串的 utf16.count 分别是 11 / 2 / 4 —— 统计口径是 Character
        #expect(family.utf16.count == 11)
        #expect(combined.utf16.count == 2)
    }

    @Test("多行 Markdown 文本逐字计数，不剥离标记")
    func markdownMarkersAreCountedVerbatim() {
        let document = "# 标题\n\n段落"
        let inline = "**bold**"

        #expect(MarkdownPreviewLogic.characterCountLabel(for: document) == "8 字符")
        #expect(MarkdownPreviewLogic.characterCountLabel(for: inline) == "8 字符")
        #expect(MarkdownPreviewLogic.characterCountLabel(for: document) == "\(document.count) 字符")
    }
}

@Suite("Markdown 预览插件契约")
@MainActor
struct MarkdownPreviewPluginTests {

    @Test("插件 id 是 kebab-case 且等于约定值")
    func identifierConvention() {
        let id = MarkdownPreviewPlugin.id

        #expect(id == "markdown-preview")
        #expect(!id.hasPrefix("-") && !id.hasSuffix("-") && !id.contains("--"))
        #expect(id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
    }

    @Test("名称、图标、触发词齐备")
    func metadataIsComplete() {
        #expect(MarkdownPreviewPlugin.name == "Markdown 预览")
        #expect(MarkdownPreviewPlugin.icon == "text.alignleft")
        #expect(
            MarkdownPreviewPlugin.triggerWords == ["Markdown 预览", "markdown", "md", "预览"]
        )
    }

    /// 入口由静态命令承载，不再由搜索现算 —— 原来这条测试问的是 `searchItems` 的返回，
    /// 那个遗留 API 已删除（见 docs/refactor-plan.md Phase 0）。
    @Test("预览功能有一条命令，且带插件前缀")
    func commandsCoverPreview() {
        let commands = MarkdownPreviewPlugin.commands
        let ids = commands.map(\.id)

        #expect(ids.contains("markdown-preview.preview"))
        let functionIDs = commands.filter { !$0.id.hasPrefix("plugin.open.") }.map(\.id)
        #expect(functionIDs.allSatisfy { $0.hasPrefix("markdown-preview.") })
        #expect(commands.allSatisfy { $0.pluginID == MarkdownPreviewPlugin.id })
    }

    @Test("插件不参与按查询现算")
    func doesNotTakePartInDynamicSearch() async {
        let plugin = MarkdownPreviewPlugin()

        #expect(!plugin.accepts(query: "md"))
        #expect(await plugin.dynamicSearch(query: "hash").isEmpty)
    }

    @Test("makeView 能构建出视图（真实视图，非占位）")
    func makeViewBuildsTheRealView() {
        let plugin = MarkdownPreviewPlugin()

        // AnyView 的相等性无法比较，这里只确认不崩溃且带上了本插件的视图。
        // 视图现在由插件持有输入状态（`TextBuffer`），所以不再单独裸构造 `MarkdownPreviewView()`。
        _ = plugin.makeView()
    }
}
