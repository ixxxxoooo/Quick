// SettingsStoreTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickCore

@Suite("设置存储")
@MainActor
struct SettingsStoreTests {

    /// 每个用例一个独立的偏好域，跑完就删
    ///
    /// 不能用 `UserDefaults.standard`：那会污染用户真实的偏好，
    /// 而且用例之间会互相看到对方写的值。
    private func makeStore() -> (SettingsStore, UserDefaults, String) {
        let suite = "quick-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("无法创建测试用 UserDefaults suite")
        }
        return (SettingsStore(defaults: defaults), defaults, suite)
    }

    @Test("没设置过的插件默认启用")
    func unsetPluginDefaultsToEnabled() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        // 这一条是「新插件默认能用」的保证：用 bool(forKey:) 直接读会把
        // 没设置过读成 false，于是所有插件一上来就是关的。
        #expect(store.isPluginEnabled("launcher"))
        #expect(store.isPluginEnabled("clipboard"))
    }

    @Test("停用后读到 false，重新启用后读到 true")
    func setAndReadBack() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setPluginEnabled("clipboard", enabled: false)
        #expect(store.isPluginEnabled("clipboard") == false)
        #expect(store.isPluginEnabled("launcher"), "只该影响被改的那个插件")

        store.setPluginEnabled("clipboard", enabled: true)
        #expect(store.isPluginEnabled("clipboard"))
    }

    @Test("停用列表只含被显式停用的插件")
    func disabledListReflectsOnlyDisabledPlugins() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setPluginEnabled("weather", enabled: false)
        store.setPluginEnabled("notes", enabled: false)

        let disabled = store.disabledPluginIDs(among: ["launcher", "weather", "notes", "calculator"])
        #expect(Set(disabled) == ["weather", "notes"])
    }

    @Test("设置跨实例持久化")
    func settingsPersistAcrossInstances() {
        let suite = "quick-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            Issue.record("无法创建测试用 UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        SettingsStore(defaults: defaults).setPluginEnabled("ocr", enabled: false)

        // 换一个实例读同一个域，模拟「重启应用」
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.isPluginEnabled("ocr") == false)
    }

    @Test("不同偏好域互不影响")
    func suitesAreIsolated() {
        let (storeA, defaultsA, suiteA) = makeStore()
        let (storeB, defaultsB, suiteB) = makeStore()
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }

        storeA.setPluginEnabled("snippets", enabled: false)

        #expect(storeA.isPluginEnabled("snippets") == false)
        #expect(storeB.isPluginEnabled("snippets"), "另一个域不该看到这次改动")
    }
}
