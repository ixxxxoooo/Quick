// SettingsSearchCatalogTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import QuickUI

@Suite("设置搜索目录")
struct SettingsSearchCatalogTests {

    @Test("条目 id 唯一：同 id 会让列表高亮与跳转串位")
    func idsAreUnique() {
        let ids = SettingsSearchCatalog.staticEntries.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("每个条目都有标题，且子标题不是英文占位")
    func entriesAreComplete() {
        for entry in SettingsSearchCatalog.staticEntries {
            #expect(!entry.title.isEmpty, "\(entry.id) 缺标题")
            #expect(entry.subtitle != "General" && entry.subtitle != "Advanced", "\(entry.id) 的子标题还是英文")
        }
    }

    @Test("中英文关键词都能搜到同一条")
    func bilingualMatching() {
        let chinese = SettingsSearchCatalog.results(for: "节假日", plugins: [])
        let english = SettingsSearchCatalog.results(for: "holiday", plugins: [])
        #expect(chinese.first?.tab == .calendar)
        #expect(chinese.map(\.id) == english.map(\.id))
    }

    @Test("空查询没有结果")
    func emptyQueryHasNoResults() {
        #expect(SettingsSearchCatalog.results(for: "  ", plugins: []).isEmpty)
    }

    @Test("每个功能页都能被搜到")
    func everyFeatureTabIsReachable() {
        let tabs = Set(SettingsSearchCatalog.staticEntries.map(\.tab))
        let required: [SettingsTab] = [
            .general, .appearance, .shortcuts, .permissions, .search, .calendar, .sqlFormatter,
            .hashCalculator, .timestampConverter, .screenshot, .superPanel, .aiService, .about
        ]
        for tab in required { #expect(tabs.contains(tab), "\(tab) 没有搜索入口") }
    }
}
