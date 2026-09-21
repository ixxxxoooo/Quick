// ScreenPlacement.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit

/// 按指针位置挑屏幕
///
/// **多显示器下「用户在看哪块屏」只有一个可靠信号：鼠标在哪。** `NSScreen.main` 是系统设置里
/// 指定的那一块主屏，跟用户此刻在哪块屏上干活没有关系 —— 拿它定位，表现就是窗口凭空跳到
/// 另一块屏上（分离窗口踩过这个坑：`NSWindow.center()` 用的就是主屏）。
///
/// 抽成纯函数是因为它的出错处全在边界上：屏幕之间的空隙（多显示器错位排列时真的存在）、
/// 两块屏的贴合边、点正好落在角落。这些靠手摆显示器试很难覆盖全。
public enum ScreenPlacement {

    /// 指针所在的那块屏幕
    ///
    /// - Parameters:
    ///   - point: 全局坐标下的点（`NSEvent.mouseLocation` 就是全局坐标）
    ///   - screens: 候选屏幕，默认全部
    /// - Returns: 命中的屏幕；指针落在屏幕之间的空隙里、或没有任何屏幕时返回 `nil`
    public static func screen(
        under point: CGPoint = NSEvent.mouseLocation,
        among screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        guard let index = screenIndex(containing: point, frames: screens.map(\.frame)) else {
            return nil
        }
        return screens[index]
    }

    /// 命中点的屏幕下标
    ///
    /// - Parameters:
    ///   - point: 全局坐标下的点
    ///   - frames: 各屏幕的 frame，顺序与调用方的屏幕数组一致
    /// - Returns: 命中的下标；落在空隙里返回 `nil`
    public static func screenIndex(containing point: CGPoint, frames: [CGRect]) -> Int? {
        // `CGRect.contains` 与 `NSMouseInRect(_, _, false)` 同为「含最小边、不含最大边」，
        // 所以两块屏贴合时那个点只会命中其中一块，不会同时命中两块。
        frames.firstIndex { $0.contains(point) }
    }
}
