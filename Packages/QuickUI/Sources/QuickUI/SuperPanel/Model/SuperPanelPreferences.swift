// SuperPanelPreferences.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 超级面板的鼠标唤出配置（纯逻辑，可单测）
public struct SuperPanelMouseConfig: Sendable, Equatable {

    public var rightLongPressEnabled: Bool
    public var middleClickEnabled: Bool
    /// 右键长按阈值（毫秒）
    public var thresholdMilliseconds: Int

    public init(
        rightLongPressEnabled: Bool,
        middleClickEnabled: Bool,
        thresholdMilliseconds: Int
    ) {
        self.rightLongPressEnabled = rightLongPressEnabled
        self.middleClickEnabled = middleClickEnabled
        self.thresholdMilliseconds = thresholdMilliseconds
    }

    public var needsListening: Bool {
        rightLongPressEnabled || middleClickEnabled
    }
}

/// 超级面板背景材质
///
/// macOS 的 `NSVisualEffectView` 不暴露连续的模糊半径，能换的只有材质本身。
/// 与其给一个「调了也没用」的模糊滑块，不如把材质本身做成可选项 —— 每个选项都真的有效果。
public enum SuperPanelMaterial: String, CaseIterable, Sendable, Identifiable {
    /// 系统给浮动面板用的材质，模糊最强
    case hud
    /// 介于两者之间
    case popover
    /// 不做背景模糊，只有一层纯色底
    case solid

    public var id: Self { self }

    public var title: String {
        switch self {
        case .hud: "毛玻璃"
        case .popover: "半透明"
        case .solid: "纯色"
        }
    }
}

/// 超级面板的外观配置
public struct SuperPanelAppearance: Sendable, Equatable {
    /// 背景不透明度，0.3…1.0（文字不受影响，只压背景）
    public var opacity: Double
    public var material: SuperPanelMaterial

    public init(opacity: Double, material: SuperPanelMaterial) {
        self.opacity = opacity
        self.material = material
    }
}

/// 超级面板偏好键与默认值
///
/// 键值沿用 `superPanel.*` 前缀：超级面板此前是一个插件，偏好已经写进用户机器；
/// 现在它升级成宿主组件，键不变只是省掉一次迁移。
public enum SuperPanelPreferences {

    public enum Key {
        public static let mouseLongPressEnabled = "superPanel.mouseLongPressEnabled"
        public static let mouseLongPressThresholdMs = "superPanel.mouseLongPressThresholdMs"
        public static let middleClickEnabled = "superPanel.middleClickEnabled"
        public static let opacity = "superPanel.opacity"
        public static let material = "superPanel.material"
        public static let showRecents = "superPanel.showRecents"
        public static let showClipboard = "superPanel.showClipboard"
        public static let quickTools = "superPanel.quickTools"
    }

    public static let defaultLongPressEnabled = true
    public static let defaultMiddleClickEnabled = true
    public static let defaultThresholdMs = 450
    public static let minThresholdMs = 50
    public static let maxThresholdMs = 1000
    public static let thresholdStepMs = 50

    public static let defaultOpacity = 0.85
    public static let minOpacity = 0.30
    public static let maxOpacity = 1.0
    public static let opacityStep = 0.05
    public static let defaultMaterial = SuperPanelMaterial.hud

    /// 从偏好读出鼠标监听配置
    public static func mouseConfiguration(from defaults: UserDefaults = .standard) -> SuperPanelMouseConfig {
        let longPress =
            defaults.object(forKey: Key.mouseLongPressEnabled) as? Bool ?? defaultLongPressEnabled
        let middle =
            defaults.object(forKey: Key.middleClickEnabled) as? Bool ?? defaultMiddleClickEnabled
        let rawThreshold =
            defaults.object(forKey: Key.mouseLongPressThresholdMs) as? Int ?? defaultThresholdMs
        return SuperPanelMouseConfig(
            rightLongPressEnabled: longPress,
            middleClickEnabled: middle,
            thresholdMilliseconds: clampedThreshold(rawThreshold)
        )
    }

    /// 从偏好读出外观配置
    public static func appearance(from defaults: UserDefaults = .standard) -> SuperPanelAppearance {
        let rawOpacity = defaults.object(forKey: Key.opacity) as? Double ?? defaultOpacity
        let material =
            (defaults.string(forKey: Key.material)).flatMap(SuperPanelMaterial.init(rawValue:))
            ?? defaultMaterial
        return SuperPanelAppearance(opacity: clampedOpacity(rawOpacity), material: material)
    }

    /// 夹紧长按阈值到 50…1000，并按 50ms 步进对齐
    public static func clampedThreshold(_ ms: Int) -> Int {
        let clamped = min(maxThresholdMs, max(minThresholdMs, ms))
        let stepped = (clamped / thresholdStepMs) * thresholdStepMs
        return max(minThresholdMs, stepped)
    }

    /// 夹紧不透明度到 0.30…1.0
    public static func clampedOpacity(_ value: Double) -> Double {
        min(maxOpacity, max(minOpacity, value))
    }
}
