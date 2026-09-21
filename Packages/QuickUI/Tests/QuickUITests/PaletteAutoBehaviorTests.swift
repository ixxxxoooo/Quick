// PaletteAutoBehaviorTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickUI

@Suite("面板自动行为")
struct PaletteAutoBehaviorTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - 自动粘贴

    @Test("刚复制过就填进搜索框")
    func prefillsWhenClipboardIsFresh() {
        #expect(
            PaletteAutoBehavior.shouldPrefillFromClipboard(
                lastClipboardChange: now.addingTimeInterval(-2),
                now: now, window: 5,
                clipboardText: "刚复制的内容", currentQuery: ""))
    }

    @Test("超过时间窗就不填")
    func doesNotPrefillWhenStale() {
        #expect(
            !PaletteAutoBehavior.shouldPrefillFromClipboard(
                lastClipboardChange: now.addingTimeInterval(-6),
                now: now, window: 5,
                clipboardText: "旧内容", currentQuery: ""))
    }

    @Test("时间窗边界算「在窗内」")
    func windowBoundaryIsInclusive() {
        // 正好 5 秒：用户看到的是「5 秒内」，所以边界该算在内
        #expect(
            PaletteAutoBehavior.shouldPrefillFromClipboard(
                lastClipboardChange: now.addingTimeInterval(-5),
                now: now, window: 5,
                clipboardText: "边界", currentQuery: ""))
    }

    @Test("关掉时永不填充")
    func offNeverPrefills() {
        #expect(
            !PaletteAutoBehavior.shouldPrefillFromClipboard(
                lastClipboardChange: now, now: now, window: 0,
                clipboardText: "内容", currentQuery: ""))
    }

    @Test("不覆盖用户已经打了一半的输入")
    func doesNotOverwriteTypedQuery() {
        #expect(
            !PaletteAutoBehavior.shouldPrefillFromClipboard(
                lastClipboardChange: now, now: now, window: 5,
                clipboardText: "剪贴板", currentQuery: "cl"))
    }

    @Test("剪贴板是空白时不填")
    func doesNotPrefillBlankClipboard() {
        for text in ["", "   ", "\n\t"] {
            #expect(
                !PaletteAutoBehavior.shouldPrefillFromClipboard(
                    lastClipboardChange: now, now: now, window: 5,
                    clipboardText: text, currentQuery: ""),
                "空白内容不该被填进搜索框：\(text.debugDescription)")
        }
    }

    @Test("从没复制过就不填")
    func doesNotPrefillWithoutTimestamp() {
        #expect(
            !PaletteAutoBehavior.shouldPrefillFromClipboard(
                lastClipboardChange: nil, now: now, window: 5,
                clipboardText: "内容", currentQuery: ""))
    }

    // MARK: - 自动清空

    @Test("放置超过空闲时间就清空")
    func clearsWhenIdle() {
        #expect(
            PaletteAutoBehavior.shouldClearStaleQuery(
                lastEditedAt: now.addingTimeInterval(-4 * 60),
                now: now, idleMinutes: 3, currentQuery: "旧查询"))
    }

    @Test("还在空闲时间内不清")
    func keepsFreshQuery() {
        #expect(
            !PaletteAutoBehavior.shouldClearStaleQuery(
                lastEditedAt: now.addingTimeInterval(-2 * 60),
                now: now, idleMinutes: 3, currentQuery: "刚打的"))
    }

    @Test("空闲时间边界算「该清」")
    func idleBoundaryClears() {
        #expect(
            PaletteAutoBehavior.shouldClearStaleQuery(
                lastEditedAt: now.addingTimeInterval(-3 * 60),
                now: now, idleMinutes: 3, currentQuery: "边界"))
    }

    @Test("搜索框本来就空时无事可做")
    func nothingToClearWhenEmpty() {
        #expect(
            !PaletteAutoBehavior.shouldClearStaleQuery(
                lastEditedAt: now.addingTimeInterval(-60 * 60),
                now: now, idleMinutes: 3, currentQuery: ""))
    }

    @Test("关掉时不清空")
    func offNeverClears() {
        #expect(
            !PaletteAutoBehavior.shouldClearStaleQuery(
                lastEditedAt: now.addingTimeInterval(-60 * 60),
                now: now, idleMinutes: 0, currentQuery: "内容"))
    }

    @Test("没有时间戳时不清空")
    func doesNotClearWithoutTimestamp() {
        // 例如查询是启动参数预填的：宁可留着，也不要莫名清掉
        #expect(
            !PaletteAutoBehavior.shouldClearStaleQuery(
                lastEditedAt: nil, now: now, idleMinutes: 3, currentQuery: "预填内容"))
    }

    @Test("选项文案与取值一致")
    func optionTitles() {
        #expect(PaletteAutoBehavior.AutoPasteWindow.fiveSeconds.rawValue == 5)
        #expect(PaletteAutoBehavior.AutoPasteWindow.off.rawValue == 0)
        #expect(PaletteAutoBehavior.AutoClearIdle.threeMinutes.rawValue == 3)
        #expect(PaletteAutoBehavior.AutoClearIdle.off.title == "关闭")
    }

    // MARK: - 读取设置

    /// 一个用完即弃的偏好域
    ///
    /// 用例之间不能共用一个 suite：Swift Testing 并行跑，共用会互相覆盖。
    private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "quick.tests.paletteAutoBehavior.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    /// 这条是回归测试：「没设置过」被读成 0 就是「关闭」，与设置页显示的默认值对不上
    @Test("没设置过时读到的是默认值，不是关闭")
    func unsetReadsDefaultNotOff() throws {
        try withIsolatedDefaults { defaults in
            #expect(PaletteAutoBehavior.pasteWindow(from: defaults) == .fiveSeconds)
            #expect(PaletteAutoBehavior.clearIdle(from: defaults) == .threeMinutes)
            #expect(PaletteAutoBehavior.defaultPasteWindow != .off)
            #expect(PaletteAutoBehavior.defaultClearIdle != .off)
        }
    }

    /// 设置页把出厂默认交给 `@AppStorage`，读取方在键不存在时回落到同一个常量
    @Test("设置页默认值与读取方默认值同源")
    func paneDefaultMatchesReaderDefault() throws {
        try withIsolatedDefaults { defaults in
            #expect(
                PaletteAutoBehavior.pasteWindow(from: defaults).rawValue
                    == PaletteAutoBehavior.defaultPasteWindow.rawValue)
            #expect(
                PaletteAutoBehavior.clearIdle(from: defaults).rawValue
                    == PaletteAutoBehavior.defaultClearIdle.rawValue)
        }
    }

    /// 「显式关掉」不能被当成「没设置过」，否则用户永远关不掉默认开启的功能
    @Test("显式关掉读成关闭")
    func explicitOffIsHonoured() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(0, forKey: SettingsKey.paletteAutoPasteSeconds)
            defaults.set(0, forKey: SettingsKey.paletteAutoClearMinutes)

            #expect(PaletteAutoBehavior.pasteWindow(from: defaults) == .off)
            #expect(PaletteAutoBehavior.clearIdle(from: defaults) == .off)
        }
    }

    @Test("设置过的取值优先于默认值")
    func storedValueWins() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(30, forKey: SettingsKey.paletteAutoPasteSeconds)
            defaults.set(10, forKey: SettingsKey.paletteAutoClearMinutes)

            #expect(PaletteAutoBehavior.pasteWindow(from: defaults) == .thirtySeconds)
            #expect(PaletteAutoBehavior.clearIdle(from: defaults) == .tenMinutes)
        }
    }

    @Test("认不出来的取值回落到默认值")
    func unknownValueFallsBack() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(7, forKey: SettingsKey.paletteAutoPasteSeconds)

            #expect(PaletteAutoBehavior.pasteWindow(from: defaults) == PaletteAutoBehavior.defaultPasteWindow)
        }
    }
}
