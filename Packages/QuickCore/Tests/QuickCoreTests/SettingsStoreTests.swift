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

    @Test("没设置过的模块默认启用")
    func unsetModuleDefaultsToEnabled() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        // 这一条是「新模块默认能用」的保证：用 bool(forKey:) 直接读会把
        // 没设置过读成 false，于是所有模块一上来就是关的。
        #expect(store.isModuleEnabled("launcher"))
        #expect(store.isModuleEnabled("clipboard"))
    }

    @Test("停用后读到 false，重新启用后读到 true")
    func setAndReadBack() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setModuleEnabled("clipboard", enabled: false)
        #expect(store.isModuleEnabled("clipboard") == false)
        #expect(store.isModuleEnabled("launcher"), "只该影响被改的那个模块")

        store.setModuleEnabled("clipboard", enabled: true)
        #expect(store.isModuleEnabled("clipboard"))
    }

    @Test("停用列表只含被显式停用的模块")
    func disabledListReflectsOnlyDisabledModules() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setModuleEnabled("weather", enabled: false)
        store.setModuleEnabled("notes", enabled: false)

        let disabled = store.disabledModuleIDs(among: ["launcher", "weather", "notes", "calculator"])
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

        SettingsStore(defaults: defaults).setModuleEnabled("ocr", enabled: false)

        // 换一个实例读同一个域，模拟「重启应用」
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.isModuleEnabled("ocr") == false)
    }

    @Test("不同偏好域互不影响")
    func suitesAreIsolated() {
        let (storeA, defaultsA, suiteA) = makeStore()
        let (storeB, defaultsB, suiteB) = makeStore()
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }

        storeA.setModuleEnabled("snippets", enabled: false)

        #expect(storeA.isModuleEnabled("snippets") == false)
        #expect(storeB.isModuleEnabled("snippets"), "另一个域不该看到这次改动")
    }
}
