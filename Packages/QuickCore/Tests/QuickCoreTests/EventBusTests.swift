// EventBusTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing
@testable import QuickCore

@MainActor
@Suite("EventBus 测试")
struct EventBusTests {

    /// 测试事件发布与接收
    @Test("发布事件后订阅者应收到事件")
    func postAndReceive() {
        let bus = EventBus.shared
        defer { bus.removeAll() }

        var received = false
        bus.on(NavigateEvent.self) { event in
            received = true
            #expect(event.pluginID == "devtools")
        }

        bus.post(NavigateEvent(pluginID: "devtools", context: ["tool": "json"]))
        #expect(received)
    }

    /// 测试取消订阅
    @Test("取消订阅后不应再收到事件")
    func unsubscribe() {
        let bus = EventBus.shared
        defer { bus.removeAll() }

        var count = 0
        let sub = bus.on(ShowHUDEvent.self) { _ in
            count += 1
        }

        bus.post(ShowHUDEvent(message: "测试"))
        #expect(count == 1)

        sub.cancel()
        bus.post(ShowHUDEvent(message: "再次"))
        #expect(count == 1)
    }

    /// 测试分离面板事件发布与接收
    @Test("DetachPanelEvent 正确传递插件 ID")
    func detachPanelEvent() {
        let bus = EventBus.shared
        defer { bus.removeAll() }

        var receivedPluginID: String?
        bus.on(DetachPanelEvent.self) { event in
            receivedPluginID = event.pluginID
        }

        bus.post(DetachPanelEvent(pluginID: "clipboard"))
        #expect(receivedPluginID == "clipboard")
    }
}
