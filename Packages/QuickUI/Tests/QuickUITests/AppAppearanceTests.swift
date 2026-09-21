// AppAppearanceTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Testing

@testable import QuickUI

@Suite("外观模式")
@MainActor
struct AppAppearanceTests {

    /// 每个用例一个独立的偏好域，用完删掉 —— 不碰用户真实的 defaults
    private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "quick.tests.appearance.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    /// 「跟随系统」必须映射成 `nil`：把选择权交回 AppKit，系统换外观时它自己跟进
    @Test("跟随系统映射成 nil")
    func systemMapsToNil() {
        #expect(AppAppearance.system.nsAppearance == nil)
    }

    @Test("浅色与深色映射到对应的 NSAppearance")
    func fixedModesMapToNamedAppearances() {
        #expect(AppAppearance.light.nsAppearance?.name == .aqua)
        #expect(AppAppearance.dark.nsAppearance?.name == .darkAqua)
    }

    /// 这条是回归测试：`quick.global.appearance` 以前是个孤儿键 —— 有键名、有文档注释，
    /// 但全仓没有读取方，于是「切换主题」永远不生效
    @Test("没设置过时跟随系统")
    func unsetFollowsSystem() throws {
        try withIsolatedDefaults { defaults in
            #expect(AppAppearance.stored(in: defaults) == .system)
        }
    }

    @Test("存过就用存的值")
    func storedValueWins() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(AppAppearance.dark.rawValue, forKey: SettingsKey.appearance)
            #expect(AppAppearance.stored(in: defaults) == .dark)

            defaults.set(AppAppearance.light.rawValue, forKey: SettingsKey.appearance)
            #expect(AppAppearance.stored(in: defaults) == .light)
        }
    }

    /// 认不出来的取值不能让外观卡在一个非法状态
    @Test("认不出来的取值回落到跟随系统")
    func unknownValueFallsBack() throws {
        try withIsolatedDefaults { defaults in
            defaults.set("midnight", forKey: SettingsKey.appearance)
            #expect(AppAppearance.stored(in: defaults) == .system)
        }
    }

    /// 设置页的选项顺序与文案
    @Test("三个选项都有文案，顺序是 跟随系统 / 浅色 / 深色")
    func optionsAreLabelled() {
        #expect(AppAppearance.allCases == [.system, .light, .dark])
        #expect(AppAppearance.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
