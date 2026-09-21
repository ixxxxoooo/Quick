// AppAppearance.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// 外观模式：跟随系统 / 固定浅色 / 固定深色
///
/// `DesignTokens` 里的颜色都是 `NSColor(name:) { appearance in ... }` 这类动态颜色，
/// 它们**在绘制时**才按当前外观解析。所以只要给 `NSApp.appearance` 赋一次值，
/// 面板、设置窗口、分离窗口就一起变了 —— 不需要逐个窗口设置，也不需要重建任何视图。
public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {

    case system
    case light
    case dark

    public var id: Self { self }

    public var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    /// 对应的 `NSAppearance`
    ///
    /// `system` 映射成 `nil`：把选择权交回 AppKit，系统切换外观时它自己跟进 ——
    /// 我们不需要轮询，也不需要为「跟随系统」单独写一条路径。
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// 从偏好里读外观设置
    ///
    /// - Parameter defaults: 偏好域（测试传自己的 suite）
    /// - Returns: 存着的取值；没设置过、或存了个认不出来的值时，跟随系统
    public static func stored(in defaults: UserDefaults = .standard) -> AppAppearance {
        defaults.string(forKey: SettingsKey.appearance)
            .flatMap(AppAppearance.init)
            ?? .system
    }
}
