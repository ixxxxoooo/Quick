// SearchSourceGroupingTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import QuickUI

@Suite("搜索来源分组")
struct SearchSourceGroupingTests {

    private func source(_ id: String, enabled: Bool = true) -> SettingsSearchSource {
        SettingsSearchSource(id: id, title: id, subtitle: "", icon: "circle", isEnabled: enabled)
    }

    @Test("按固定分类顺序分组，空组不出现，组内保持原顺序")
    func groupsInStableOrder() {
        let groups = SearchSourceGroup.grouping([
            source("json-formatter"), source("launcher"), source("clipboard"), source("sql-formatter"),
        ])
        #expect(groups.map(\.category) == [.system, .productivity, .developer])
        #expect(groups[2].sources.map(\.id) == ["json-formatter", "sql-formatter"])
    }

    @Test("认不出的来源进「其他」，不会丢项")
    func unknownGoesToOther() {
        let groups = SearchSourceGroup.grouping([source("mystery"), source("launcher")])
        #expect(groups.map(\.category) == [.system, .other])
        #expect(groups.flatMap(\.sources).count == 2)
    }

    @Test("宿主的文件搜索归到系统组")
    func fileSearchIsSystem() {
        #expect(SearchSourceCategory.category(forSourceID: "filesearch") == .system)
    }

    @Test("已开数量以本地覆盖为准")
    func enabledCountHonoursOverrides() {
        let group = SearchSourceGroup(
            category: .system, sources: [source("launcher"), source("sysmonitor", enabled: false)])
        #expect(group.enabledCount() == 1)
        #expect(group.enabledCount(overrides: ["sysmonitor": true]) == 2)
        #expect(group.enabledCount(overrides: ["launcher": false]) == 0)
    }

    /// 19 个内置插件 id 必须都落在明确分类里，新增插件忘了归类时这里会提醒
    @Test("全部内置插件都有明确分类")
    func everyBuiltInPluginHasACategory() {
        let ids = [
            "launcher", "systemcontrol", "clipboard", "calculator", "calendar", "ai", "translator",
            "json-formatter", "sql-formatter", "base64-codec", "url-codec", "uuid-generator",
            "hash-calculator", "timestamp-converter", "text-diff", "sysmonitor", "killprocess",
            "networktools", "screenshot",
        ]
        for id in ids {
            #expect(SearchSourceCategory.category(forSourceID: id) != .other, "\(id) 没有归类")
        }
    }
}
