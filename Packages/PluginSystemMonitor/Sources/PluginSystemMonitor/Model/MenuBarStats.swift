// MenuBarStats.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 菜单栏摘要的文字格式（纯逻辑）
enum MenuBarStats {

    /// 采样与刷新的节奏
    ///
    /// 不低于 2 秒：菜单栏数字再勤也没人看得出区别，而常驻采样的开销要和「始终在跑」相称。
    static func refreshSeconds(configured: Int) -> Int {
        max(2, configured)
    }

    /// 摘要文字：`CPU 12%  内存 63%`
    ///
    /// 百分比补到两位宽（`%2d`），数字位数变化时整段不抖。输入夹到 0–100。
    static func title(cpuPercent: Double, memoryPercent: Double) -> String {
        func clamp(_ value: Double) -> Int { Int(max(0, min(100, value.rounded()))) }
        return String(format: "CPU %2d%%  内存 %2d%%", clamp(cpuPercent), clamp(memoryPercent))
    }
}
