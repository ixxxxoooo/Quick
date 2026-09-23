// SystemMonitorSamplingTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginSystemMonitor

// MARK: - 纯映射

@Suite("系统监控采样间隔")
struct SystemMonitorSamplingTests {

    @Test("间隔只认设置页给出的四档，其余一律回落到 2 秒")
    func intervalMapping() {
        for choice in SystemMonitorSampling.choices {
            #expect(SystemMonitorSampling.interval(storedValue: choice) == choice)
        }
        // 没写过（integer(forKey:) 返回 0）与手改坏的值
        #expect(SystemMonitorSampling.interval(storedValue: 0) == 2)
        #expect(SystemMonitorSampling.interval(storedValue: 3) == 2)
        #expect(SystemMonitorSampling.interval(storedValue: -1) == 2)
        #expect(SystemMonitorSampling.interval(storedValue: 3600) == 2)
    }

    @Test("设置页里的档位没有 0：0 会让采样循环变成忙等")
    func zeroIsNotAChoice() {
        #expect(!SystemMonitorSampling.choices.contains(0))
        #expect(SystemMonitorSampling.choices.allSatisfy { $0 > 0 })
        #expect(SystemMonitorSampling.defaultInterval == 2)
    }

    @Test("间隔跟着键走，没设置过就是设置页显示的 2 秒")
    func configuredIntervalFollowsTheKey() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "com.ixxxxoooo.quick.tests.sysmonitor.\(UUID().uuidString)"))

        #expect(SystemMonitorSampling.configuredInterval(defaults: defaults) == 2)

        defaults.set(1, forKey: PluginSettingKey.SystemMonitor.interval)
        #expect(SystemMonitorSampling.configuredInterval(defaults: defaults) == 1)

        defaults.set(10, forKey: PluginSettingKey.SystemMonitor.interval)
        #expect(SystemMonitorSampling.configuredInterval(defaults: defaults) == 10)

        defaults.set(7, forKey: PluginSettingKey.SystemMonitor.interval)
        #expect(SystemMonitorSampling.configuredInterval(defaults: defaults) == 2)
    }
}

// MARK: - 采样循环

/// 采样循环是视图 `.task` 里跑的东西，所以用例要在主 actor 上驱动它。
@MainActor
@Suite("系统监控采样循环")
struct SystemMonitorSamplingLoopTests {

    /// 数一轮采样跑了多少次。刷新动作由测试注入，绝不真的起 `ps`。
    private final class TickCounter {
        private(set) var count = 0
        func tick() { count += 1 }
    }

    private static func makeDefaults(interval: Int) -> UserDefaults? {
        let defaults = UserDefaults(suiteName: "com.ixxxxoooo.quick.tests.sysmonitor.\(UUID().uuidString)")
        defaults?.set(interval, forKey: PluginSettingKey.SystemMonitor.interval)
        return defaults
    }

    /// 在给定时间窗内跑采样循环，返回它采样了多少轮
    private static func ticks(
        of scanner: ProcessScanner,
        within window: Duration
    ) async -> Int {
        let counter = TickCounter()
        let task = Task { await scanner.startSampling(tick: { counter.tick() }) }
        try? await Task.sleep(for: window)
        task.cancel()
        await task.value
        return counter.count
    }

    @Test("采样循环按设置里的间隔等：1 秒的窗口里至少跑两轮")
    func fastIntervalSamplesMoreThanOnce() async throws {
        let scanner = ProcessScanner(defaults: try #require(Self.makeDefaults(interval: 1)))

        let count = await Self.ticks(of: scanner, within: .milliseconds(1600))

        #expect(count >= 2, "间隔 1 秒时 1.6 秒的窗口应该采到至少两轮，实际 \(count) 轮")
    }

    @Test("间隔 10 秒时同样的窗口里只跑一轮")
    func slowIntervalSamplesOnce() async throws {
        let scanner = ProcessScanner(defaults: try #require(Self.makeDefaults(interval: 10)))

        let count = await Self.ticks(of: scanner, within: .milliseconds(1200))

        #expect(count == 1, "间隔 10 秒时 1.2 秒的窗口只能采到一轮，实际 \(count) 轮")
    }

    @Test("循环被取消后立刻停下")
    func cancellationStopsTheLoop() async throws {
        let scanner = ProcessScanner(defaults: try #require(Self.makeDefaults(interval: 1)))

        let count = await Self.ticks(of: scanner, within: .milliseconds(300))
        // 循环已经结束：再等一会儿计数不会变
        try? await Task.sleep(for: .milliseconds(300))

        #expect(count == 1)
    }

    @Test("stopSampling 会取消由 startSamplingIfNeeded 拉起的循环")
    func stopSamplingCancelsManagedTask() async throws {
        let scanner = ProcessScanner(defaults: try #require(Self.makeDefaults(interval: 1)))
        let counter = TickCounter()

        scanner.startSamplingIfNeeded(tick: { counter.tick() })
        try? await Task.sleep(for: .milliseconds(300))
        #expect(scanner.isSampling)
        let mid = counter.count
        #expect(mid >= 1)

        scanner.stopSampling()
        #expect(!scanner.isSampling)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(counter.count == mid, "停止后不应再产生 tick，中点 \(mid) 最终 \(counter.count)")
    }

    @Test("面板隐藏停采样，视图仍挂着时再显示会恢复")
    func panelVisibilityPausesAndResumes() async throws {
        let scanner = ProcessScanner(defaults: try #require(Self.makeDefaults(interval: 1)))
        let counter = TickCounter()

        // 不走 noteViewAppeared，避免测试里拉起真实 ps/sysctl
        scanner.setResumeWhenVisible(true)
        scanner.startSamplingIfNeeded(tick: { counter.tick() })
        try? await Task.sleep(for: .milliseconds(200))
        #expect(scanner.isSampling)

        scanner.notePanelVisibility(false)
        #expect(!scanner.isSampling)
        let paused = counter.count
        try? await Task.sleep(for: .milliseconds(400))
        #expect(counter.count == paused)

        scanner.notePanelVisibility(true)
        #expect(scanner.isSampling)
        scanner.stopSampling()
        scanner.noteViewDisappeared()
        #expect(!scanner.isSampling)

        // 视图已消失：再显示面板也不该空转
        scanner.notePanelVisibility(true)
        #expect(!scanner.isSampling)
    }

    @Test("扫描器把设置里的间隔透出来")
    func scannerExposesTheConfiguredInterval() throws {
        let scanner = ProcessScanner(defaults: try #require(Self.makeDefaults(interval: 10)))

        #expect(scanner.samplingInterval == 10)
    }
}

/// 插件里的扫描器读的是标准偏好存储，这里也只能写标准存储 —— 换成独立 suite 就测不到接线了。
/// 标准存储是进程共享的，所以用例串行并自己收尾。
@MainActor
@Suite("系统监控插件的设置接线", .serialized)
struct SystemMonitorPluginSettingsTests {

    private static let intervalKey = PluginSettingKey.SystemMonitor.interval

    @Test("插件持有的扫描器读的是标准偏好里的间隔")
    func pluginScannerReadsTheStandardDefault() async throws {
        let previous = UserDefaults.standard.object(forKey: Self.intervalKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: Self.intervalKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.intervalKey)
            }
        }

        UserDefaults.standard.set(10, forKey: Self.intervalKey)
        #expect(SystemMonitorPlugin().scanner.samplingInterval == 10)

        UserDefaults.standard.set(1, forKey: Self.intervalKey)
        #expect(SystemMonitorPlugin().scanner.samplingInterval == 1)
    }
}
