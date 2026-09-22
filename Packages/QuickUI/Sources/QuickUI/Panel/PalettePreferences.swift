// PalettePreferences.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics
import Foundation
import QuickCore

/// 外观页写进偏好、面板真正要读的那几项
///
/// 没写过的键按设置页上的默认值处理。`bool(forKey:)` 对缺失键返回 false，
/// 不能直接拿来当「默认打开」。
public enum PalettePreferences {

    /// 面板缩放。没设置过是 1.1，和设计基准一致
    public static var scale: CGFloat {
        guard UserDefaults.standard.object(forKey: SettingsKey.paletteScale) != nil else { return 1.1 }
        let value = UserDefaults.standard.double(forKey: SettingsKey.paletteScale)
        if value == 1 || value == 1.1 || value == 1.2 { return value }
        return 1.1
    }

    /// 相对设计令牌（1.1）的倍数，用来把已经按 1.1 排好的面板再缩放到用户选的档
    public static var scaleFactor: CGFloat {
        let base = DesignTokens.panelScale
        guard base > 0 else { return 1 }
        return scale / base
    }

    /// 主面板高度。拖过上下边之后用记住的值，否则用当前缩放下的设计高度
    public static var panelHeight: CGFloat {
        let fallback = DesignTokens.Size.panelHeight * scaleFactor
        guard UserDefaults.standard.object(forKey: SettingsKey.paletteHeight) != nil else { return fallback }
        let stored = UserDefaults.standard.double(forKey: SettingsKey.paletteHeight)
        guard stored > 0 else { return fallback }
        return stored
    }

    /// 主面板宽度。拖过左右边之后用记住的值，否则用当前缩放下的设计宽度
    public static var panelWidth: CGFloat {
        let fallback = DesignTokens.Size.panelWidth * scaleFactor
        guard UserDefaults.standard.object(forKey: SettingsKey.paletteWidth) != nil else { return fallback }
        let stored = UserDefaults.standard.double(forKey: SettingsKey.paletteWidth)
        guard stored > 0 else { return fallback }
        return stored
    }

    /// 记住用户拖出来的尺寸
    public static func setPanelSize(_ size: CGSize) {
        UserDefaults.standard.set(Double(size.width), forKey: SettingsKey.paletteWidth)
        UserDefaults.standard.set(Double(size.height), forKey: SettingsKey.paletteHeight)
    }

    /// 换缩放档时丢掉手动拖出来的尺寸，回到该档的设计尺寸
    public static func clearPanelSize() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.paletteWidth)
        UserDefaults.standard.removeObject(forKey: SettingsKey.paletteHeight)
    }

    /// 把拖出来的高度夹在最矮和当前屏幕之间
    public static func clampedPanelHeight(_ height: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let floor = DesignTokens.Size.panelMinHeight
        let ceiling = max(floor, maxHeight)
        return min(max(floor, height), ceiling)
    }

    /// 把拖出来的宽度夹在最窄和当前屏幕之间
    public static func clampedPanelWidth(_ width: CGFloat, maxWidth: CGFloat) -> CGFloat {
        let floor = DesignTokens.Size.panelMinWidth
        let ceiling = max(floor, maxWidth)
        return min(max(floor, width), ceiling)
    }

    /// 为真时面板出现在主显示器，否则跟鼠标所在屏幕
    public static var usesMainScreen: Bool {
        UserDefaults.standard.string(forKey: SettingsKey.paletteScreen) == "main"
    }

    public static var showResultIcons: Bool { flag(SettingsKey.showResultIcons, default: true) }
    public static var showBottomBarHints: Bool { flag(SettingsKey.showBottomBarHints, default: true) }
    public static var showMenuBar: Bool { flag(SettingsKey.showInMenuBar, default: true) }

    /// 背景遮罩的加减。0 是现在的样子，正数更实，负数更透
    public static var scrimBoost: Double {
        let raw = UserDefaults.standard.object(forKey: SettingsKey.panelTransparency) as? Int ?? 0
        return Double(raw) / 100
    }

    private static func flag(_ key: String, default defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }
}
