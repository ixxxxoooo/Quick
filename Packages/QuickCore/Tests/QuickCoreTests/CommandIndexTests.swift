// CommandIndexTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import QuickCore

@Suite("命令索引")
struct CommandIndexTests {

    private func command(
        id: String,
        pluginID: String,
        title: String,
        keywords: [String] = [],
        showsWhenQueryEmpty: Bool = false
    ) -> IndexedCommand {
        IndexedCommand(
            CommandDescriptor(
                id: id,
                pluginID: pluginID,
                pluginName: pluginID,
                title: title,
                keywords: keywords,
                icon: "circle",
                showsWhenQueryEmpty: showsWhenQueryEmpty
            )
        )
    }

    @Test("空查询每个插件只留一条入口")
    func emptyQueryKeepsOneEntryPerPlugin() {
        let commands = [
            command(id: "a.1", pluginID: "a", title: "甲", showsWhenQueryEmpty: true),
            command(id: "a.2", pluginID: "a", title: "乙", showsWhenQueryEmpty: true),
            command(id: "b.1", pluginID: "b", title: "丙", showsWhenQueryEmpty: false),
            command(id: "c.1", pluginID: "c", title: "丁", showsWhenQueryEmpty: true)
        ]
        let hits = CommandIndex.matching(commands, query: "")
        #expect(hits.map(\.command.id) == ["a.1", "c.1"])
        #expect(hits.allSatisfy { $0.relevance == CommandIndex.emptyQueryRelevance })
    }

    @Test("关键词能命中，不匹配的命令不出现")
    func keywordMatch() {
        let commands = [
            command(
                id: "systemcontrol.lock", pluginID: "systemcontrol", title: "锁定屏幕", keywords: ["锁屏", "lock"]),
            command(
                id: "systemcontrol.sleep", pluginID: "systemcontrol", title: "睡眠", keywords: ["睡眠", "sleep"])
        ]
        let hits = CommandIndex.matching(commands, query: "锁屏")
        #expect(hits.map(\.command.id) == ["systemcontrol.lock"])
        #expect(hits[0].relevance > 0)
    }

    @Test("关闭的命令不在快照里就不会被搜到")
    func absentCommandIsNotSearchable() {
        let commands = [
            command(id: "systemcontrol.sleep", pluginID: "systemcontrol", title: "睡眠", keywords: ["睡眠"])
        ]
        let hits = CommandIndex.matching(commands, query: "锁屏")
        #expect(hits.isEmpty)
    }
}

@Suite("关键字解析")
struct KeywordResolverTests {

    private func command(title: String, keywords: [String]) -> CommandDescriptor {
        CommandDescriptor(
            id: title,
            pluginID: "demo",
            pluginName: "示例",
            title: title,
            keywords: keywords,
            icon: "circle"
        )
    }

    @Test("关键字和标题都能唯一命中")
    func uniqueKeywordOrTitle() {
        let commands = [
            command(title: "锁定屏幕", keywords: ["锁屏", "lock"]),
            command(title: "剪贴板", keywords: ["剪贴板", "clipboard"])
        ]
        #expect(KeywordResolver.match(query: "锁屏", commands: commands)?.title == "锁定屏幕")
        #expect(KeywordResolver.match(query: "LOCK", commands: commands)?.title == "锁定屏幕")
        #expect(KeywordResolver.match(query: "剪贴板", commands: commands)?.title == "剪贴板")
    }

    @Test("对不上或同时对上多条时不猜测")
    func rejectsEmptyAndAmbiguous() {
        let commands = [
            command(title: "笔记", keywords: ["笔记"]),
            command(title: "备忘", keywords: ["笔记"])
        ]
        #expect(KeywordResolver.match(query: "  ", commands: commands) == nil)
        #expect(KeywordResolver.match(query: "没有", commands: commands) == nil)
        #expect(KeywordResolver.match(query: "笔记", commands: commands) == nil)
    }
}
