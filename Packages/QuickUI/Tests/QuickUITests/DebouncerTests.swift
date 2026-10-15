// DebouncerTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Synchronization
import Testing

@testable import QuickUI

@MainActor
@Suite("防抖计算")
struct DebouncerTests {

    /// 收集回写结果
    @MainActor final class Sink {
        var values: [Int] = []
    }

    private func waitUntil(_ timeout: Double = 3, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("小输入同步回写，没有任何延迟")
    func smallInputRunsInline() {
        let debouncer = Debouncer(delay: .milliseconds(50), inlineThreshold: 100)
        let sink = Sink()
        debouncer.schedule(weight: 10, work: { 42 }) { sink.values.append($0) }
        #expect(sink.values == [42], "小输入必须在调用返回前就已回写")
    }

    @Test("大输入先等防抖再后台算")
    func largeInputIsDeferred() async {
        let debouncer = Debouncer(delay: .milliseconds(30), inlineThreshold: 100)
        let sink = Sink()
        debouncer.schedule(weight: 1000, work: { 7 }) { sink.values.append($0) }
        #expect(sink.values.isEmpty, "大输入不该同步回写")
        await waitUntil { !sink.values.isEmpty }
        #expect(sink.values == [7])
    }

    @Test("连续输入只落地最后一次")
    func onlyTheLatestWins() async {
        let debouncer = Debouncer(delay: .milliseconds(60), inlineThreshold: 100)
        let sink = Sink()
        for value in 1...5 {
            debouncer.schedule(weight: 1000, work: { value }) { sink.values.append($0) }
        }
        await waitUntil { !sink.values.isEmpty }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(sink.values == [5])
    }

    @Test("后到的小输入会作废还没落地的大输入")
    func smallInputSupersedesPendingLarge() async {
        let debouncer = Debouncer(delay: .milliseconds(60), inlineThreshold: 100)
        let sink = Sink()
        debouncer.schedule(weight: 1000, work: { 1 }) { sink.values.append($0) }
        debouncer.schedule(weight: 1, work: { 2 }) { sink.values.append($0) }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(sink.values == [2], "旧的大输入结果不能覆盖新的")
    }

    @Test("取消后不再回写")
    func cancelStopsPendingWork() async {
        let debouncer = Debouncer(delay: .milliseconds(50), inlineThreshold: 100)
        let sink = Sink()
        debouncer.schedule(weight: 1000, work: { 9 }) { sink.values.append($0) }
        debouncer.cancel()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(sink.values.isEmpty)
    }

    @Test("大输入的计算在后台线程执行，结果在主线程回写")
    func largeWorkRunsOffTheMainThread() async {
        let debouncer = Debouncer(delay: .milliseconds(10), inlineThreshold: 100)
        final class Probe: Sendable {
            let ranOnMain = Mutex<Bool?>(nil)
        }
        let probe = Probe()
        let sink = Sink()
        var appliedOnMain: Bool?
        debouncer.schedule(weight: 1000, work: {
            probe.ranOnMain.withLock { $0 = Thread.isMainThread }
            return 1
        }) {
            appliedOnMain = Thread.isMainThread
            sink.values.append($0)
        }
        await waitUntil { !sink.values.isEmpty }
        #expect(probe.ranOnMain.withLock { $0 } == false, "大输入的计算不该占用主线程")
        #expect(appliedOnMain == true, "回写必须回到主线程")
    }
}
