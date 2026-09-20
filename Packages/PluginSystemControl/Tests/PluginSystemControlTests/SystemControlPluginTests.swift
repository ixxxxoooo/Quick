// SystemControlPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginSystemControl

@Suite("系统控制插件")
@MainActor
struct SystemControlPluginTests {

    @Test("插件 id 符合约定")
    func identifierConvention() {
        #expect(SystemControlPlugin.id == "systemcontrol")
        #expect(!SystemControlPlugin.name.isEmpty)
        #expect(!SystemControlPlugin.icon.isEmpty)
    }

    @Test("每个系统操作都有完整的元信息")
    func everyActionIsFullyDescribed() {
        for action in SystemAction.allCases {
            #expect(!action.title.isEmpty, "\(action.rawValue) 缺少标题")
            #expect(!action.description.isEmpty, "\(action.rawValue) 缺少描述")
            #expect(!action.icon.isEmpty, "\(action.rawValue) 缺少图标")
            #expect(!action.keywords.isEmpty, "\(action.rawValue) 缺少搜索关键词")
            #expect(
                action.keywords.allSatisfy { !$0.isEmpty },
                "\(action.rawValue) 含空关键词，空关键词会被模糊匹配放行"
            )
        }
    }

    @Test("rawValue 唯一")
    func rawValuesAreUnique() {
        let rawValues = SystemAction.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("空查询不返回结果")
    func emptyQueryYieldsNothing() async {
        let plugin = SystemControlPlugin()
        #expect(await plugin.searchItems(query: "").isEmpty)
    }

    @Test("按关键词可以命中对应操作")
    func searchMatchesByKeyword() async {
        let plugin = SystemControlPlugin()
        let results = await plugin.searchItems(query: "锁屏")

        let ids = results.map(\.id)
        #expect(ids.contains("systemcontrol.lock"), "「锁屏」应命中锁定屏幕操作，实际命中 \(ids)")
    }

    @Test("结果带插件前缀且互不重复")
    func resultIdentifiersArePrefixedAndUnique() async {
        let plugin = SystemControlPlugin()
        let results = await plugin.searchItems(query: "关")

        let ids = results.map(\.id)
        #expect(Set(ids).count == ids.count, "同一插件内的 SearchableItem.id 必须唯一")
        #expect(ids.allSatisfy { $0.hasPrefix("systemcontrol.") })
        #expect(results.allSatisfy { $0.pluginID == SystemControlPlugin.id })
    }

    @Test("相关度落在 0...1 区间")
    func relevanceStaysInRange() async {
        let plugin = SystemControlPlugin()
        let results = await plugin.searchItems(query: "重启")

        #expect(!results.isEmpty)
        for item in results {
            #expect(item.relevance >= 0 && item.relevance <= 1, "相关度越界: \(item.relevance)")
        }
    }
}
