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

    @Test("触发词命中返回入口")
    func trigger() async {
        let plugin = KillProcessPlugin()
        #expect(await plugin.searchItems(query: "杀进程").count == 1)
        #expect(await plugin.searchItems(query: "weather").isEmpty)
    }
}
