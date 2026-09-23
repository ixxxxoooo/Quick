// MouseTriggerMonitorTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import QuickPlatform

@Suite("MouseTriggerMonitor")
struct MouseTriggerMonitorTests {

    @Test("阈值夹紧到 50…1500")
    func thresholdClamping() {
        #expect(MouseTriggerMonitor.Configuration.clampedThreshold(0) == 50)
        #expect(MouseTriggerMonitor.Configuration.clampedThreshold(49) == 50)
        #expect(MouseTriggerMonitor.Configuration.clampedThreshold(450) == 450)
        #expect(MouseTriggerMonitor.Configuration.clampedThreshold(2000) == 1500)
    }

    @Test("两边都关时不需要监听")
    func needsListeningRequiresEitherSide() {
        var config = MouseTriggerMonitor.Configuration(
            rightLongPressEnabled: false,
            middleClickEnabled: false
        )
        #expect(!config.needsListening)

        config.middleClickEnabled = true
        #expect(config.needsListening)

        config.middleClickEnabled = false
        config.rightLongPressEnabled = true
        #expect(config.needsListening)
    }

    @Test("init 会对阈值做夹紧")
    func initClampsThreshold() {
        let config = MouseTriggerMonitor.Configuration(thresholdMilliseconds: 9999)
        #expect(config.thresholdMilliseconds == 1500)
    }
}
