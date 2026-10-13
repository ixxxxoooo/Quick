// MenuBarStatsTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginSystemMonitor

@Suite("菜单栏摘要格式")
struct MenuBarStatsFormatTests {

    @Test("百分比补到两位宽，整段宽度稳定")
    func padsToStableWidth() {
        #expect(MenuBarStats.title(cpuPercent: 7.2, memoryPercent: 63.4) == "CPU  7%  内存 63%")
        #expect(MenuBarStats.title(cpuPercent: 100, memoryPercent: 0) == "CPU 100%  内存  0%")
    }

    @Test("越界输入被夹到 0–100，不产出负数或超过 100 的百分比")
    func clampsInput() {
        #expect(MenuBarStats.title(cpuPercent: -5, memoryPercent: 250) == "CPU  0%  内存 100%")
    }

    @Test("刷新间隔不低于 2 秒")
    func refreshFloor() {
        #expect(MenuBarStats.refreshSeconds(configured: 1) == 2)
        #expect(MenuBarStats.refreshSeconds(configured: 5) == 5)
    }

    @Test("内存采样落在合理范围")
    func memorySampleIsPlausible() throws {
        let percent = try #require(MenuBarStatsRunner.memoryUsedPercent())
        #expect(percent > 0 && percent <= 100)
    }
}

/// 开关接线：真的改了标准偏好，常驻采样就该发出文字，关掉就该清除。
/// 标准偏好进程共享，所以串行并自己收尾。
@Suite("菜单栏摘要接线", .serialized)
@MainActor
struct MenuBarStatsWiringTests {

    private static let key = PluginSettingKey.SystemMonitor.showMenuBarStats

    /// 等到事件序列里出现满足条件的一条，最多 `seconds` 秒
    private func waitForText(
        _ box: TextBox, seconds: Double, where predicate: @escaping (String?) -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if box.values.contains(where: predicate) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    @MainActor final class TextBox { var values: [String?] = [] }

    @Test("开着时发出摘要文字，关掉后发出清除")
    func enabledPostsTextAndDisabledClears() async {
        let saved = UserDefaults.standard.object(forKey: Self.key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: Self.key) }
            else { UserDefaults.standard.removeObject(forKey: Self.key) }
        }
        UserDefaults.standard.set(true, forKey: Self.key)

        let box = TextBox()
        let subscription = EventBus.shared.on(MenuBarTextEvent.self) { box.values.append($0.text) }
        defer { subscription.cancel() }

        let runner = MenuBarStatsRunner()
        runner.start()
        defer { runner.stop() }

        // 第一轮建基线，第二轮（约 2 秒后）才有增量可显示
        let shown = await waitForText(box, seconds: 6) { $0?.hasPrefix("CPU") == true }
        #expect(shown, "开关打开后应当发出摘要文字")

        UserDefaults.standard.set(false, forKey: Self.key)
        // 采样循环最长睡一个刷新周期（≥2 秒）才会重新读到开关
        let cleared = await waitForText(box, seconds: 8) { $0 == nil }
        #expect(cleared, "开关关掉后应当发出清除")
    }
}
