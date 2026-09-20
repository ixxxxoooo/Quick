// WeatherService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreLocation
import Foundation
import QuickCore

/// 天气服务
///
/// 使用 WeatherKit 获取天气数据。
/// 需要 Apple Developer 账号启用 WeatherKit 能力。
///
/// ## 定位权限策略（不要改）
///
/// **任何自动路径都不申请定位权限。** 插件激活、后台刷新、定时任务都不允许调用
/// `requestWhenInUseAuthorization()` —— 那会让每次启动都弹系统权限框。
/// 唯一的申请入口是 `requestAuthorization()`，而它只应由用户的明确动作触发
/// （例如搜索「天气」后出现的那条授权入口）。
///
/// 未授权时 `refresh()` 只读取状态并记下来，由界面给出可操作的提示。
@MainActor
@Observable
final class WeatherService: NSObject, CLLocationManagerDelegate {

    /// 天气信息
    struct WeatherInfo: Sendable {
        let summary: String
        let detail: String
        let icon: String
        let temperature: Double
    }

    /// 天气不可用的原因
    ///
    /// 分成三种而不是一个「失败」，因为每种要给用户的下一步动作不同。
    enum UnavailableReason: Sendable {
        /// 还没问过用户，可以申请
        case needsPermission
        /// 用户拒绝过，或系统定位服务被关闭 —— 只能去系统设置里开
        case permissionDenied
        /// 已授权但拿不到位置（室内、定位服务异常、超时）
        case locationUnavailable
    }

    private(set) var currentInfo: WeatherInfo?
    private(set) var unavailableReason: UnavailableReason?
    private(set) var isLoading = false

    private let locationManager = CLLocationManager()
    private let log = QuickLog.plugin(WeatherPlugin.id)

    /// 获取位置的超时
    ///
    /// 取代原先「发起请求后 sleep 3 秒再读结果」的写法：那个写法既慢又不保证拿到值。
    private static let locationTimeout = Duration.seconds(8)

    /// 定位精度到公里级就够天气用，也最省电
    private static let desiredAccuracy = kCLLocationAccuracyKilometer

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = Self.desiredAccuracy
    }

    // MARK: - 权限

    /// 当前定位授权状态
    var authorizationStatus: CLAuthorizationStatus { locationManager.authorizationStatus }

    /// 是否已获得定位授权
    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .authorizedAlways: true
        default: false
        }
    }

    /// 申请定位权限
    ///
    /// **只有用户的明确动作可以调用它。** 见类型文档里的定位权限策略。
    func requestAuthorization() {
        guard authorizationStatus == .notDetermined else {
            log.debug("定位权限已决定，不再重复申请")
            return
        }
        log.notice("用户主动申请定位权限")
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - 刷新

    /// 刷新天气数据
    ///
    /// 未授权时**不会**发起申请，只把原因记下来。
    func refresh() async {
        guard !isLoading else {
            log.debug("已有刷新在进行中，跳过本次请求")
            return
        }
        isLoading = true
        defer { isLoading = false }

        guard isAuthorized else {
            unavailableReason =
                authorizationStatus == .notDetermined ? .needsPermission : .permissionDenied
            currentInfo = nil
            log.notice(
                "定位权限不可用，跳过天气刷新（状态 \(self.authorizationStatus.logName, privacy: .public)）")
            return
        }

        do {
            let coordinate = try await fetchCoordinate()
            unavailableReason = nil
            // WeatherKit 需要真实的 Apple Developer 账号，这里先给出框架接口。
            currentInfo = WeatherInfo(
                summary: "天气服务就绪",
                detail:
                    "位置: \(String(format: "%.2f", coordinate.latitude)), \(String(format: "%.2f", coordinate.longitude))",
                icon: "cloud.sun",
                temperature: 0
            )
            log.notice("已获取位置，天气服务就绪")
        } catch {
            unavailableReason = .locationUnavailable
            currentInfo = nil
            log.error("获取位置失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 获取当前天气
    func currentWeather() async -> WeatherInfo? {
        if currentInfo == nil { await refresh() }
        return currentInfo
    }

    // MARK: - 定位

    /// 只传坐标，不传 `CLLocation`
    ///
    /// `CLLocation` 是引用类型且带一堆我们不需要的字段；跨任务边界只传两个 `Double`，
    /// 就没有任何 `Sendable` 疑问。
    private struct Coordinate: Sendable {
        let latitude: Double
        let longitude: Double
    }

    private enum LocationError: Error, LocalizedError {
        case timedOut
        case unavailable

        var errorDescription: String? {
            switch self {
            case .timedOut: "获取位置超时"
            case .unavailable: "系统未能提供位置"
            }
        }
    }

    /// 取一次位置
    ///
    /// 用 `CLLocationUpdate.liveUpdates()`（现代异步 API）而不是
    /// `requestLocation()` + 代理回调 + 固定 sleep。
    /// 超时用竞速任务实现，所以最坏情况是 8 秒返回，而不是永远挂着。
    private func fetchCoordinate() async throws -> Coordinate {
        try await withThrowingTaskGroup(of: Coordinate.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location {
                        return Coordinate(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                        )
                    }
                }
                throw LocationError.unavailable
            }
            group.addTask {
                try await Task.sleep(for: Self.locationTimeout)
                throw LocationError.timedOut
            }

            defer { group.cancelAll() }
            guard let coordinate = try await group.next() else {
                throw LocationError.unavailable
            }
            return coordinate
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.log.notice("定位权限状态变更: \(status.logName, privacy: .public)")
            if self.isAuthorized {
                await self.refresh()
            } else {
                self.unavailableReason = .permissionDenied
                self.currentInfo = nil
            }
        }
    }
}

// MARK: - 日志用短名

extension CLAuthorizationStatus {
    /// 日志里的稳定短名（英文，便于过滤）
    fileprivate var logName: String {
        switch self {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorizedAlways: "authorizedAlways"
        case .authorizedWhenInUse: "authorizedWhenInUse"
        case .authorized: "authorized"
        @unknown default: "unknown"
        }
    }
}
