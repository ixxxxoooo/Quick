// HotKeyServiceTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickPlatform
import Carbon.HIToolbox
import QuickCore

@MainActor
@Suite("全局快捷键服务")
struct HotKeyServiceTests {

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "quick-hotkey-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("无法创建测试用 UserDefaults suite")
        }
        return (defaults, suite)
    }

    /// start/stop 不应崩溃，并可设置回调
    @Test("启停与回调绑定")
    func startStopAndCallback() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = HotKeyService(defaults: defaults)
        var fired: String?
        service.onCommand = { fired = $0 }
        service.start()
        service.handleHotKeyPressedForTesting()
        #expect(fired == CommandID.togglePalette)
        service.stop()
    }

    @Test("同一组合键不能绑到两条命令")
    func rejectsConflictingShortcut() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = HotKeyService(defaults: defaults)
        let shortcut = KeyShortcut(carbonKeyCode: 49, carbonModifiers: optionKey)
        let first = service.setBinding(shortcut, for: "systemcontrol.lock", registerNow: false)
        let second = service.setBinding(shortcut, for: "systemcontrol.sleep", registerNow: false)
        #expect(first == .applied)
        #expect(second == .conflict(commandID: "systemcontrol.lock"))
        #expect(service.binding(for: "systemcontrol.sleep") == nil)
    }

    @Test("旧热键键迁移成命令 id")
    func migratesLegacyKeys() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcut = KeyShortcut(carbonKeyCode: 49, carbonModifiers: optionKey)
        let data = try? JSONEncoder().encode(shortcut)
        defaults.set(data, forKey: "hotkey.togglePalette")
        defaults.set(data, forKey: "hotkey.systemAction.lock")
        defaults.set(data, forKey: "hotkey.plugin.clipboard")
        defaults.set(data, forKey: "hotkey.app.com.apple.Safari")

        HotKeyMigration.migrate(defaults: defaults)

        #expect(defaults.data(forKey: "hotkey.togglePalette") == nil)
        #expect(defaults.data(forKey: HotKeyAction(commandID: CommandID.togglePalette).defaultsKey) != nil)
        #expect(
            defaults.data(forKey: HotKeyAction(commandID: CommandID.systemAction("lock")).defaultsKey) != nil)
        #expect(
            defaults.data(forKey: HotKeyAction(commandID: CommandID.openPlugin("clipboard")).defaultsKey)
                != nil)
        #expect(
            defaults.data(
                forKey: HotKeyAction(commandID: CommandID.launchApp("com.apple.Safari")).defaultsKey) != nil
        )
        HotKeyMigration.migrate(defaults: defaults)
        #expect(defaults.bool(forKey: HotKeyMigration.flag))
    }
}
