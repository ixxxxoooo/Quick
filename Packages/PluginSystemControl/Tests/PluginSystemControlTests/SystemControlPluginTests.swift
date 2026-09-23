// SystemControlPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
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

    @Test("functionCommands 与 CommandID 一致且别名键为 system.<rawValue>")
    func functionCommandsAlignWithCommandID() {
        for descriptor in SystemControlPlugin.functionCommands {
            #expect(descriptor.id.hasPrefix("systemcontrol."))
            #expect(descriptor.pluginID == SystemControlPlugin.id)
            let raw = String(descriptor.id.dropFirst("systemcontrol.".count))
            #expect(descriptor.aliasKey == "system.\(raw)")
            #expect(SystemAction(rawValue: raw) != nil)
        }
    }
}

@Suite("系统操作元数据")
struct SystemActionMetadataTests {

    @Test("命令 id 格式为 systemcontrol.<rawValue>")
    func commandIDFormat() {
        for action in SystemAction.allCases {
            #expect(CommandID.systemAction(action.rawValue) == "systemcontrol.\(action.rawValue)")
        }
    }

    @Test("英文关键词能命中对应操作")
    func englishKeywordsMapToActions() {
        let samples: [(String, SystemAction)] = [
            ("lock screen", .lockScreen),
            ("sleep", .sleep),
            ("reboot", .restart),
            ("shut down", .shutdown),
            ("log out", .logout),
            ("screen saver", .screenSaver),
            ("empty trash", .emptyTrash),
            ("eject all", .ejectAll),
            ("dark mode", .toggleDarkMode),
            ("do not disturb", .toggleDoNotDisturb)
        ]
        for (keyword, expected) in samples {
            #expect(
                expected.keywords.contains { $0.caseInsensitiveCompare(keyword) == .orderedSame },
                "\(expected.rawValue) 应包含关键词 \(keyword)")
        }
    }

    @Test("中文口语关键词覆盖主要操作")
    func chineseKeywordsCoverCoreActions() {
        let samples: [(String, SystemAction)] = [
            ("锁屏", .lockScreen),
            ("睡眠", .sleep),
            ("重启", .restart),
            ("关机", .shutdown),
            ("注销", .logout),
            ("屏保", .screenSaver),
            ("废纸篓", .emptyTrash),
            ("推出磁盘", .ejectAll),
            ("深色模式", .toggleDarkMode),
            ("勿扰", .toggleDoNotDisturb)
        ]
        for (keyword, expected) in samples {
            #expect(
                expected.keywords.contains(keyword),
                "\(expected.rawValue) 应包含中文关键词 \(keyword)")
        }
    }
}

@Suite("系统操作自动化提示")
struct SystemActionAutomationCopyTests {

    @Test("权限不足时的 HUD 文案格式固定")
    func permissionHintFormat() {
        #expect(SystemActionAutomationCopy.permissionHint(action: "睡眠") == "睡眠失败：需要「自动化」权限")
        #expect(
            SystemActionAutomationCopy.permissionHint(action: "清空废纸篓")
                == "清空废纸篓失败：需要「自动化」权限")
    }
}
