// SuperPanelMousePreferences.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 超级面板鼠标唤出偏好（纯逻辑，可单测；不依赖 AppKit）
struct SuperPanelMouseConfig: Sendable, Equatable {
    var rightLongPressEnabled: Bool
    var middleClickEnabled: Bool
    /// 右键长按阈值（毫秒）
    var thresholdMilliseconds: Int

    var needsListening: Bool {
        rightLongPressEnabled || middleClickEnabled
    }
}

enum SuperPanelMousePreferences: Sendable {

    /// 右键长按默认开启（对齐用户在 Fasty 的使用习惯）
    static let defaultLongPressEnabled = true
    /// 中键默认开启
    static let defaultMiddleClickEnabled = true
    /// 默认长按阈值（毫秒）
    static let defaultThresholdMs: Int = 450
    static let minThresholdMs: Int = 50
    static let maxThresholdMs: Int = 1000
    static let thresholdStepMs: Int = 50

    /// 从 UserDefaults 读出监听配置
    static func configuration(from defaults: UserDefaults = .standard) -> SuperPanelMouseConfig {
        let longPress =
            defaults.object(forKey: PluginSettingKey.SuperPanel.mouseLongPressEnabled) as? Bool
            ?? defaultLongPressEnabled
        let middle =
            defaults.object(forKey: PluginSettingKey.SuperPanel.middleClickEnabled) as? Bool
            ?? defaultMiddleClickEnabled
        let rawThreshold =
            defaults.object(forKey: PluginSettingKey.SuperPanel.mouseLongPressThresholdMs) as? Int
            ?? defaultThresholdMs
        return SuperPanelMouseConfig(
            rightLongPressEnabled: longPress,
            middleClickEnabled: middle,
            thresholdMilliseconds: clampedThreshold(rawThreshold)
        )
    }

    /// 夹紧长按阈值到 50…1000，并按 50ms 步进对齐
    static func clampedThreshold(_ ms: Int) -> Int {
        let clamped = min(maxThresholdMs, max(minThresholdMs, ms))
        let stepped = (clamped / thresholdStepMs) * thresholdStepMs
        return max(minThresholdMs, stepped)
    }
}
