// KillProcessPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginKillProcess

@Suite("结束进程列表解析")
struct KillProcessListingTests {

    @Test("解析 ps 行并过滤非法 pid")
    func parsesRows() {
        let output = """
              1  0.0  0.1  1234 /sbin/launchd
            532  1.5  2.3  2048 /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
              0  1.0  1.0   100 /bin/zero
            abc  1.0  1.0   100 /bin/bad
            """
        let records = KillProcessListing.parse(output)
        #expect(records.count == 2)
        #expect(records[0].name == "launchd")
        #expect(records[1].name == "Finder")
        #expect(records[1].cpuPercent == 1.5)
        #expect(records[1].memoryText == "2.0 MB")
    }

    @Test("按名称 / PID / 路径过滤")
    func filters() {
        let records = [
            ProcessRecord(
                id: 10, name: "Cursor", path: "/Apps/Cursor", cpuPercent: 1, memoryPercent: 1,
                rssKilobytes: 100),
            ProcessRecord(
                id: 20, name: "Finder", path: "/System/Finder", cpuPercent: 1, memoryPercent: 1,
                rssKilobytes: 100)
        ]
        #expect(
            KillProcessListing.filter(records, query: "cur", searchPath: false, searchPID: false).map(\.id)
                == [10])
        #expect(
            KillProcessListing.filter(records, query: "20", searchPath: false, searchPID: true).map(\.id) == [
                20
            ])
        #expect(
            KillProcessListing.filter(records, query: "System", searchPath: true, searchPID: false).map(\.id)
                == [20])
        #expect(KillProcessListing.filter(records, query: "", searchPath: false, searchPID: false).count == 2)
    }
}

@Suite("结束进程偏好")
struct KillProcessPreferencesTests {

    @Test("排序与间隔回落")
    func mapping() {
        #expect(KillProcessPreferences.sort(storedValue: nil) == .cpu)
        #expect(KillProcessPreferences.sort(storedValue: "memory") == .memory)
        #expect(KillProcessPreferences.sort(storedValue: "x") == .cpu)
        #expect(KillProcessPreferences.interval(storedValue: 0) == 3)
        #expect(KillProcessPreferences.interval(storedValue: 5) == 5)
    }
}

@Suite("结束进程插件契约")
@MainActor
struct KillProcessPluginContractTests {

    @Test("元信息齐备且支持标题栏搜索")
    func metadata() {
        #expect(KillProcessPlugin.id == "killprocess")
        #expect(KillProcessPlugin.supportsPanelSearch)
        #expect(KillProcessPlugin.name == "结束进程")
        #expect(!KillProcessPlugin.triggerWords.isEmpty)
    }

    @Test("触发词命中返回入口")
    func trigger() async {
        let plugin = KillProcessPlugin()
        #expect(await plugin.searchItems(query: "杀进程").count == 1)
        #expect(await plugin.searchItems(query: "weather").isEmpty)
    }
}
