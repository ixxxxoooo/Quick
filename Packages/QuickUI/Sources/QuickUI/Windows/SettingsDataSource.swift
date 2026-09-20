// SettingsDataSource.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 设置窗口里的一行模块
public struct SettingsModule: Identifiable, Sendable {

    /// 模块 ID
    public let id: String

    /// 模块显示名
    public let name: String

    /// 模块图标（SF Symbol 名）
    public let icon: String

    /// 初始化
    /// - Parameters:
    ///   - id: 模块 ID
    ///   - name: 显示名
    ///   - icon: SF Symbol 名
    public init(id: String, name: String, icon: String) {
        self.id = id
        self.name = name
        self.icon = icon
    }
}

/// 设置页里的一项系统权限
public enum SettingsPermission: String, CaseIterable, Sendable {

    case accessibility
    case screenCapture
    case location

    /// 显示名
    public var title: String {
        switch self {
        case .accessibility: "辅助功能"
        case .screenCapture: "屏幕录制"
        case .location: "定位服务"
        }
    }

    /// SF Symbol 名
    public var systemImage: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenCapture: "rectangle.dashed.badge.record"
        case .location: "location"
        }
    }

    /// 这个权限用来干什么
    ///
    /// 必须写清楚：权限页最忌讳「要求授权但不说用途」，
    /// 用户唯一能做的判断就是看这句话。
    public var purpose: String {
        switch self {
        case .accessibility:
            "用于窗口管理（移动/缩放其他应用的窗口）。系统只允许已授权的应用这样做。"
        case .screenCapture:
            "用于截图与窗口捕获。macOS 只允许已授权的应用读取屏幕内容。"
        case .location:
            "用于天气模块。只在你主动查看天气时申请，不会在启动时弹出。"
        }
    }
}

/// 一项权限的当前状态
public struct SettingsPermissionState: Sendable {

    /// 是否已授权
    public let isGranted: Bool

    /// 是否还能由应用主动发起申请
    ///
    /// 已经拒绝过的权限系统不会再弹框，只能去系统设置里手动打开 ——
    /// 这时界面必须改成「打开系统设置」而不是给一个点了没反应的按钮。
    public let canRequest: Bool

    /// 初始化
    /// - Parameters:
    ///   - isGranted: 是否已授权
    ///   - canRequest: 是否还能主动申请
    public init(isGranted: Bool, canRequest: Bool) {
        self.isGranted = isGranted
        self.canRequest = canRequest
    }
}

/// 设置窗口的数据源与动作
///
/// 用协议把设置界面和组装层隔开：设置在 `QuickUI`，而模块清单与系统能力
/// （登录项、快捷键、权限）只有组装层看得到。
/// **`QuickUI` 因此既不认识模块，也不认识 `QuickPlatform`** —— 依赖方向保持不变。
///
/// 由 `AppCore` 实现。
@MainActor
public protocol SettingsDataSource: AnyObject {

    // MARK: - 通用

    /// 是否已开启开机自启
    var isLaunchAtLoginEnabled: Bool { get }

    /// 设置开机自启
    func setLaunchAtLogin(_ enabled: Bool)

    /// 全局快捷键的可读描述，如 `⌥Space`
    var hotKeyDescription: String { get }

    // MARK: - 模块

    /// 全部模块（按显示名排序）
    ///
    /// 名字不叫 `modules`：组装层已经有一个 `modules`（模块实例），同名不同型无法共存。
    var moduleEntries: [SettingsModule] { get }

    /// 模块当前是否启用
    func isModuleEnabled(_ id: String) -> Bool

    /// 设置模块启用状态；实现方负责持久化并同步模块实例
    func setModuleEnabled(_ id: String, enabled: Bool)

    // MARK: - 权限

    /// 某项权限的当前状态
    func permissionState(_ permission: SettingsPermission) -> SettingsPermissionState

    /// 申请某项权限（只有 `canRequest` 为真时才有意义）
    func requestPermission(_ permission: SettingsPermission)

    /// 打开该项权限对应的系统设置面板
    func openPermissionSettings(_ permission: SettingsPermission)

    // MARK: - 关于

    /// 版本信息，如 `1.0.0 (1)`
    var versionDescription: String { get }

    /// Bundle ID
    var bundleIdentifier: String { get }

    /// 面板几何的可读描述，如 `825 × 523 · 圆角 29`
    var panelGeometryDescription: String { get }
}
