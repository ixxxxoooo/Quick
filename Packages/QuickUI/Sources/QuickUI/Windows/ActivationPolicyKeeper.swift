// ActivationPolicyKeeper.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// 应用激活策略的**唯一持有者**
///
/// 应用平时是 `.accessory`：不进 Dock、也不进 ⌘Tab 切换器。但有两种窗口需要「像普通窗口那样
/// 被对待」—— 设置窗口和 AI 网页窗口，它们一旦从别的应用切走，用户就再也找不回来
/// （accessory 应用不在切换器里）。所以谁在场谁登记，最后一个人走时恢复 `.accessory`。
///
/// **按持有者集合记账，不用计数器。** 同一个持有者重复登记（窗口反复显示）不会把账算错，
/// 少 Release 一次也不会让策略永远停在 `.regular` 上；而且两个窗口同时开着时，谁先关都不会
/// 把对方的 Dock 身份带走。
@MainActor
public enum ActivationPolicyKeeper {

    /// 当前登记在册的持有者
    private static var holders: Set<String> = []

    /// 按当前登记情况应当使用的策略
    ///
    /// 单独暴露出来是为了能直接断言：测试进程里 `setActivationPolicy` 不一定会真的改变
    /// 进程的策略（它没有 Dock），但「该用哪个策略」这件事必须确定。
    public static var requiredPolicy: NSApplication.ActivationPolicy {
        holders.isEmpty ? .accessory : .regular
    }

    /// 登记「我需要在场期间应用有 Dock 身份」
    ///
    /// - Parameter holder: 持有者标识（同一个窗口每次都传同一个值，重复调用是幂等的）
    public static func retain(_ holder: String) {
        guard holders.insert(holder).inserted else { return }
        apply()
    }

    /// 注销登记
    ///
    /// - Parameter holder: 与 `retain` 相同的标识
    public static func release(_ holder: String) {
        guard holders.remove(holder) != nil else { return }
        apply()
    }

    /// 把策略落到 `NSApp` 上
    private static func apply() {
        let policy = requiredPolicy
        NSApp.setActivationPolicy(policy)
        QuickLog.ui.debug(
            "激活策略已应用：\(policy == .regular ? "regular" : "accessory", privacy: .public)，持有者 \(holders.count, privacy: .public) 个"
        )
    }
}
