// ActivationPolicyKeeperTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Testing

@testable import QuickUI

/// 应用激活策略的持有者
///
/// 断言的是 `requiredPolicy` 而不是 `NSApp.activationPolicy()`：测试进程没有 Dock，
/// `setActivationPolicy` 不一定会真的改变进程策略，但「该用哪个策略」必须确定。
///
/// `.serialized`：持有者是**全局**一份账，并行跑会让彼此看到对方的登记。
@Suite("激活策略持有者", .serialized)
@MainActor
struct ActivationPolicyKeeperTests {

    @Test("没有持有者时是 accessory")
    func accessoryWhenEmpty() {
        #expect(ActivationPolicyKeeper.requiredPolicy == .accessory)
    }

    @Test("有人登记就进 regular，最后一个释放后回到 accessory")
    func retainThenRelease() {
        ActivationPolicyKeeper.retain("test.a")
        #expect(ActivationPolicyKeeper.requiredPolicy == .regular)

        ActivationPolicyKeeper.release("test.a")
        #expect(ActivationPolicyKeeper.requiredPolicy == .accessory)
    }

    /// 窗口会反复显示，登记必须是幂等的 —— 否则一次多余的 retain 会让 Dock 图标永远留着
    @Test("重复登记同一个持有者不会把账算错")
    func retainIsIdempotent() {
        ActivationPolicyKeeper.retain("test.b")
        ActivationPolicyKeeper.retain("test.b")
        #expect(ActivationPolicyKeeper.requiredPolicy == .regular)

        ActivationPolicyKeeper.release("test.b")
        #expect(ActivationPolicyKeeper.requiredPolicy == .accessory)
    }

    /// 设置窗口与 AI 窗口可能同时开着：谁先关都不能把对方的 Dock 身份带走
    @Test("多个持有者互不影响")
    func holdersAreIndependent() {
        ActivationPolicyKeeper.retain("test.c")
        ActivationPolicyKeeper.retain("test.d")

        ActivationPolicyKeeper.release("test.c")
        #expect(ActivationPolicyKeeper.requiredPolicy == .regular)

        ActivationPolicyKeeper.release("test.d")
        #expect(ActivationPolicyKeeper.requiredPolicy == .accessory)
    }

    @Test("释放没登记过的持有者是安全的空操作")
    func releaseUnknownIsNoop() {
        ActivationPolicyKeeper.release("test.never-registered")
        #expect(ActivationPolicyKeeper.requiredPolicy == .accessory)
    }
}
