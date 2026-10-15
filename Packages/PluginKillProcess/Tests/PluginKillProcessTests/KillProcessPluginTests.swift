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

    @Test("无法解析的行被跳过，整段乱码得到空列表")
    func unparseableOutputIsEmpty() {
        #expect(KillProcessListing.parse("not ps output at all").isEmpty)
        #expect(KillProcessListing.parse("").isEmpty)
    }

    @Test("ps 参数随排序口径变化")
    func argumentsFollowSortMode() {
        #expect(KillProcessListing.arguments(sort: .cpu) == ["-axo", KillProcessListing.columnSpec, "-r"])
        #expect(KillProcessListing.arguments(sort: .memory) == ["-axo", KillProcessListing.columnSpec, "-m"])
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

@MainActor
@Suite("结束进程服务")
struct KillProcessServiceTests {

    @Test("applyScanResults 永不列出宿主自身 PID")
    func applyScanResultsFiltersSelfPID() {
        let service = KillProcessService()
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let records = [
            ProcessRecord(
                id: selfPID, name: "Quick", path: "/Quick", cpuPercent: 1, memoryPercent: 1,
                rssKilobytes: 100),
            ProcessRecord(
                id: 42, name: "Finder", path: "/Finder", cpuPercent: 1, memoryPercent: 1,
                rssKilobytes: 100)
        ]
        service.applyScanResults(records)
        #expect(service.processes.map(\.id) == [42])
    }

    private final class TickCounter {
        private(set) var count = 0
        func tick() { count += 1 }
    }

    private static func makeDefaults(interval: Int) -> UserDefaults? {
        let defaults = UserDefaults(suiteName: "com.ixxxxoooo.quick.tests.killprocess.\(UUID().uuidString)")
        defaults?.set(interval, forKey: PluginSettingKey.KillProcess.refreshInterval)
        return defaults
    }

    private static func ticks(
        of service: KillProcessService,
        within window: Duration
    ) async -> Int {
        let counter = TickCounter()
        let task = Task { await service.startSampling(tick: { counter.tick() }) }
        try? await Task.sleep(for: window)
        task.cancel()
        await task.value
        return counter.count
    }

    @Test("采样循环按设置间隔运行")
    func samplingLoopRespectsInterval() async throws {
        let service = KillProcessService(defaults: try #require(Self.makeDefaults(interval: 1)))
        let count = await Self.ticks(of: service, within: .milliseconds(1600))
        #expect(count >= 2, "间隔 1 秒时 1.6 秒窗口应至少两轮，实际 \(count)")
    }

    @Test("stopSampling 取消由 startSamplingIfNeeded 拉起的循环")
    func stopSamplingCancelsManagedTask() async throws {
        let service = KillProcessService(defaults: try #require(Self.makeDefaults(interval: 1)))
        let counter = TickCounter()

        service.startSamplingIfNeeded(tick: { counter.tick() })
        try? await Task.sleep(for: .milliseconds(300))
        #expect(service.isSampling)
        let mid = counter.count
        #expect(mid >= 1)

        service.stopSampling()
        #expect(!service.isSampling)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(counter.count == mid)
    }

    @Test("面板隐藏停采样，视图仍挂着时再显示会恢复")
    func panelVisibilityPausesAndResumes() async throws {
        let service = KillProcessService(defaults: try #require(Self.makeDefaults(interval: 1)))
        let counter = TickCounter()

        service.setResumeWhenVisible(true)
        service.startSamplingIfNeeded(tick: { counter.tick() })
        try? await Task.sleep(for: .milliseconds(200))
        #expect(service.isSampling)

        service.notePanelVisibility(false)
        #expect(!service.isSampling)
        let paused = counter.count
        try? await Task.sleep(for: .milliseconds(400))
        #expect(counter.count == paused)

        service.notePanelVisibility(true)
        #expect(service.isSampling)
        service.stopSampling()
        service.noteViewDisappeared()
        #expect(!service.isSampling)

        service.notePanelVisibility(true)
        #expect(!service.isSampling)
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

    /// 单面板插件只暴露唯一入口命令，触发词收敛到 `triggerWords`。
    @Test("单面板插件只暴露打开插件入口命令")
    func commandsCoverKill() {
        let commands = KillProcessPlugin.commands
        #expect(commands.map(\.id) == ["plugin.open.killprocess"])
        #expect(commands.allSatisfy { $0.pluginID == KillProcessPlugin.id })
    }

    @Test("插件不参与按查询现算")
    func doesNotTakePartInDynamicSearch() async {
        let plugin = KillProcessPlugin()

        #expect(!plugin.accepts(query: "杀进程"))
        #expect(await plugin.dynamicSearch(query: "weather").isEmpty)
    }
}

@Suite("结束进程的二次确认策略")
struct KillConfirmPolicyTests {

    @Test("普通进程的普通结束不确认")
    func plainTerminateOfOrdinaryProcessSkipsConfirmation() {
        #expect(
            !KillConfirmPolicy.needsConfirmation(
                force: false, processName: "Cursor", confirmForceKill: true))
    }

    @Test("强制结束按设置决定是否确认")
    func forceKillFollowsTheSetting() {
        #expect(
            KillConfirmPolicy.needsConfirmation(
                force: true, processName: "Cursor", confirmForceKill: true))
        #expect(
            !KillConfirmPolicy.needsConfirmation(
                force: true, processName: "Cursor", confirmForceKill: false))
    }

    @Test("系统核心进程无论设置如何都要确认")
    func protectedProcessesAlwaysAsk() {
        for name in KillConfirmPolicy.protectedNames {
            #expect(
                KillConfirmPolicy.needsConfirmation(
                    force: false, processName: name, confirmForceKill: false),
                "\(name) 是核心进程，普通结束也必须确认")
        }
    }

    @Test("Finder 与 Dock 被杀会自动重启，不算核心进程")
    func finderAndDockAreNotProtected() {
        #expect(!KillConfirmPolicy.protectedNames.contains("Finder"))
        #expect(!KillConfirmPolicy.protectedNames.contains("Dock"))
    }

    @Test("设置缺省时强制确认为开")
    func confirmForceKillDefaultsToOn() {
        let suite = UserDefaults(suiteName: "killprocess.confirm.\(UUID().uuidString)")!
        #expect(KillProcessPreferences.confirmForceKill(defaults: suite))
        suite.set(false, forKey: PluginSettingKey.KillProcess.confirmForceKill)
        #expect(!KillProcessPreferences.confirmForceKill(defaults: suite))
    }

    @Test("确认文案点名目标进程")
    func messageNamesTheProcess() {
        #expect(KillConfirmPolicy.message(force: true, processName: "Cursor").contains("Cursor"))
        #expect(KillConfirmPolicy.message(force: false, processName: "WindowServer").contains("核心"))
    }
}

@Suite("进程副标题路径")
struct ProcessDisplayPathTests {

    private func record(path: String) -> ProcessRecord {
        ProcessRecord(
            id: 1, name: "x", path: path, cpuPercent: 0, memoryPercent: 0, rssKilobytes: 0)
    }

    @Test("家目录下的路径缩成 ~")
    func homeAbbreviated() {
        #expect(record(path: "/Users/a/Apps/x").displayPath(home: "/Users/a") == "~/Apps/x")
    }

    @Test("恰好是家目录本身")
    func homeItself() {
        #expect(record(path: "/Users/a").displayPath(home: "/Users/a") == "~")
    }

    @Test("名字前缀相同的另一个目录不能误缩")
    func similarPrefixNotAbbreviated() {
        #expect(record(path: "/Users/ab/x").displayPath(home: "/Users/a") == "/Users/ab/x")
    }

    @Test("系统路径原样返回，空路径没有副标题")
    func systemAndEmpty() {
        #expect(record(path: "/usr/sbin/cfprefsd").displayPath(home: "/Users/a") == "/usr/sbin/cfprefsd")
        #expect(record(path: "").displayPath(home: "/Users/a") == nil)
    }

    @Test("家目录为空或根目录时不缩写")
    func degenerateHome() {
        #expect(record(path: "/x").displayPath(home: "/") == "/x")
        #expect(record(path: "/x").displayPath(home: "") == "/x")
    }
}
