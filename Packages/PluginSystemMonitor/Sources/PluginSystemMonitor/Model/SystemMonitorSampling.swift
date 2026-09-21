// SystemMonitorSampling.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 系统监控的采样间隔
///
/// 间隔决定「两轮刷新之间等多久」，是纯映射：设置页的档位是 1/2/5/10 秒，
/// 存储里可能是别的任何整数（没写过是 0，手改过是任意值）。
enum SystemMonitorSampling {

    /// 设置页里可选的档位（秒）
    static let choices = [1, 2, 5, 10]

    /// 设置页在「从未设置过」时显示的档位
    static let defaultInterval = 2

    /// 存储值 → 合法间隔
    ///
    /// 非法值一律回落到设置页显示的默认档：采样间隔是定时器的节奏，
    /// 一个 0 会让循环变成忙等，一个负数则会让 `Task.sleep` 直接报错。
    static func interval(storedValue: Int) -> Int {
        choices.contains(storedValue) ? storedValue : defaultInterval
    }

    /// 当前设置里的采样间隔
    ///
    /// 每次采样轮次结束时重新读键：设置页把 2 秒改成 10 秒后，下一轮就按新值等。
    static func configuredInterval(defaults: UserDefaults = .standard) -> Int {
        interval(storedValue: defaults.integer(forKey: PluginSettingKey.SystemMonitor.interval))
    }
}
