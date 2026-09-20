// HotKeyServiceTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing
@testable import QuickPlatform

@MainActor
@Suite("全局快捷键服务")
struct HotKeyServiceTests {

    /// start/stop 不应崩溃，并可设置回调
    @Test("启停与回调绑定")
    func startStopAndCallback() {
        let service = HotKeyService()
        var toggled = false
        service.onTogglePalette = { toggled = true }
        service.start()
        // 直接触发内部处理，模拟热键按下
        service.handleHotKeyPressedForTesting()
        #expect(toggled)
        service.stop()
    }
}
