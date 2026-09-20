// WeatherAvailability.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 天气不可用的原因
///
/// 分成三种而不是一个「失败」，因为每种要给用户的下一步动作不同。
enum WeatherUnavailableReason: Sendable, Equatable {
    /// 还没问过用户，可以申请
    case needsPermission
    /// 用户拒绝过，或系统定位服务被关闭 —— 只能去系统设置里开
    case permissionDenied
    /// 已授权但拿不到位置（室内、定位服务异常、超时）
    case locationUnavailable
}

/// 天气插件对定位授权状态的最小视图
///
/// `CLAuthorizationStatus` 属于 CoreLocation，Model 层不能 import 它；而
/// 「已授权 / 还没问过 / 被拒绝」这三档以及它对应的用户下一步动作是纯逻辑。
/// 所以服务层只负责把框架状态翻译成这个类型，判断逻辑留在这里，可独立测试。
///
/// 注意 `.restricted`（家长控制等）与 `.denied` 合并：两者用户都无法在应用内
/// 自行解除，给出的下一步动作相同，都是「去系统设置」。
enum WeatherAuthorization: Sendable {
    /// 还没问过用户
    case notDetermined
    /// 已授权（`whenInUse` 或 `always`）
    case authorized
    /// 被拒绝、被限制，或系统定位服务整体关闭
    case denied

    /// 是否已获得定位授权
    var isAuthorized: Bool { self == .authorized }

    /// 未授权时的不可用原因；已授权返回 nil
    ///
    /// `refresh()` 在未授权分支里用它决定给用户哪条提示：只有「还没问过」
    /// 才能申请权限，其余都只能引导去系统设置。
    var unavailableReason: WeatherUnavailableReason? {
        switch self {
        case .notDetermined: .needsPermission
        case .denied: .permissionDenied
        case .authorized: nil
        }
    }
}
