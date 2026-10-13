// ReentryGateTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import PluginScreenshot

@Suite("防重入门")
struct ReentryGateTests {

    @Test("第一次进入成功，第二次被挡住")
    func secondEntryBlocked() {
        var gate = ReentryGate()
        let first = gate.tryEnter()
        let second = gate.tryEnter()
        #expect(first)
        #expect(!second)
    }

    @Test("离开后可以再次进入")
    func reenterAfterLeave() {
        var gate = ReentryGate()
        _ = gate.tryEnter()
        gate.leave()
        let again = gate.tryEnter()
        #expect(again)
    }
}
