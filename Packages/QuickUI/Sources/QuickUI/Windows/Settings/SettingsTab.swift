// SettingsTab.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 设置窗口的分栏
///
/// 用枚举而不是数组下标：`List` 的选中值必须是稳定标识，
/// 用下标会在增删分栏时错位。
enum SettingsTab: String, CaseIterable, Identifiable {

    case general
    case modules
    case permissions
    case about

    var id: Self { self }

    /// 侧边栏标题
    var title: String {
        switch self {
        case .general: "通用"
        case .modules: "模块"
        case .permissions: "权限"
        case .about: "关于"
        }
    }

    /// 侧边栏图标（SF Symbol 名）
    var systemImage: String {
        switch self {
        case .general: "switch.2"
        case .modules: "square.grid.2x2"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}
