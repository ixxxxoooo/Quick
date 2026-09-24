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
        #expect(await plugin.dynamicSearch(query: "").isEmpty)
    }

    /// 关键词 → 操作的映射现在由静态命令承载（每条命令带 `SystemAction.keywords`），
    /// 搜索不再现算。原来这条测试问的是 `searchItems` 的返回，那个遗留 API 已删除
    /// （见 docs/refactor-plan.md Phase 0）。
    @Test("按关键词可以命中对应操作")
    func commandsMatchByKeyword() {
        let commands = SystemControlPlugin.functionCommands
        let lock = commands.first { $0.id == "systemcontrol.lock" }

        #expect(lock != nil, "缺少锁定屏幕命令")
        #expect(
            lock?.keywords.contains("锁屏") == true,
            "「锁屏」应在锁定屏幕命令的关键词里，实际 \(lock?.keywords ?? [])")
    }

    /// 每条系统操作都要有命令，否则它在设置页和热键里都不存在
    @Test("每个 SystemAction 都有一条命令")
    func everyActionHasACommand() {
        let ids = Set(SystemControlPlugin.functionCommands.map(\.id))
        for action in SystemAction.allCases {
            #expect(ids.contains(CommandID.systemAction(action.rawValue)), "\(action.rawValue) 没有命令")
        }
    }

    @Test("功能命令 id 带插件前缀且互不重复")
    func resultIdentifiersArePrefixedAndUnique() {
        let ids = SystemControlPlugin.functionCommands.map(\.id)

        #expect(Set(ids).count == ids.count, "同一插件内的命令 id 必须唯一")
        #expect(ids.allSatisfy { $0.hasPrefix("systemcontrol.") })
        #expect(
            SystemControlPlugin.functionCommands.allSatisfy {
                $0.pluginID == SystemControlPlugin.id
            })
    }

    /// 别名解析靠 `CommandDescriptor.aliasKey`，设置页才能把用户改的名字绑到具体操作上
    @Test("每条命令都有别名键")
    func everyCommandCarriesAliasKey() {
        for descriptor in SystemControlPlugin.functionCommands {
            #expect(descriptor.aliasKey?.hasPrefix("system.") == true)
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

    /// 回归测试：勿扰模式在 macOS 上没有公开的切换 API，曾经留了一个能搜到、
    /// 点了只弹「暂未实现」的命令 —— 那种占位比没有更糟，用户会以为功能坏了
    @Test("不提供没有实现的占位操作")
    func noUnimplementedPlaceholderActions() {
        #expect(SystemAction(rawValue: "dnd") == nil)
        #expect(!SystemAction.allCases.contains { $0.title.contains("暂未实现") })
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
            ("dark mode", .toggleDarkMode)
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
            ("深色模式", .toggleDarkMode)
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
