// PluginDefaultsTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickCore

@Suite("PluginDefaults")
struct PluginDefaultsTests {

    @Test("未写入的键按默认值返回，与 false 直读区分")
    func unsetKeyUsesDefault() {
        let key = "quick-tests-plugin-defaults-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        #expect(PluginDefaults.isEnabled(key))
        #expect(PluginDefaults.isEnabled(key, default: false) == false)
    }

    @Test("写入 false 后读到 false，写入 true 后读到 true")
    func explicitBoolRoundTrip() {
        let key = "quick-tests-plugin-defaults-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        UserDefaults.standard.set(false, forKey: key)
        #expect(PluginDefaults.isEnabled(key, default: true) == false)

        UserDefaults.standard.set(true, forKey: key)
        #expect(PluginDefaults.isEnabled(key, default: false))
    }
}
