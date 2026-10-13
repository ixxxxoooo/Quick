// AccessibilityAdaptation.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI

/// 「增强对比度」下的不透明度抬升
///
/// 纯函数，单独拎出来是为了能断言：抬得太少没效果，抬得太多会盖住内容。
enum ContrastBoost {

    /// 高对比下的放大倍数
    static let factor = 1.8

    /// 高对比下的下限：再淡的线条也要到这个浓度才看得见（只对非零值生效）
    static let floor = 0.12

    static func alpha(_ alpha: Double, highContrast: Bool) -> Double {
        guard highContrast, alpha > 0 else { return alpha }
        return min(1, max(alpha * factor, floor))
    }
}

/// 「减弱动态效果」
///
/// 系统开关打开时，所有位移 / 淡入淡出一律变成瞬时。动画只是润色，丢掉不影响任何功能。
/// 读 `NSWorkspace` 而不是 SwiftUI 的 `\.accessibilityReduceMotion`：AppKit 里的动画
/// （HUD、胶囊）拿不到 SwiftUI 环境，两边必须同一个判断。
public enum Motion {

    /// 是否应当减弱动态效果
    @MainActor
    public static var isReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 解析时长：减弱时为 0
    public static func duration(_ duration: TimeInterval, reduced: Bool) -> TimeInterval {
        reduced ? 0 : duration
    }

    /// AppKit 动画时长
    @MainActor
    public static func duration(_ duration: TimeInterval) -> TimeInterval {
        Self.duration(duration, reduced: isReduced)
    }

    /// SwiftUI 动画；减弱时为 `nil`（即无动画）
    @MainActor
    public static func animation(_ animation: Animation) -> Animation? {
        isReduced ? nil : animation
    }

    /// 带减弱判断的 `withAnimation`
    @MainActor
    public static func withAnimation<Result>(
        _ animation: Animation, _ body: () throws -> Result
    ) rethrows -> Result {
        try SwiftUI.withAnimation(Self.animation(animation), body)
    }
}
