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
@MainActor
final class WeatherService: NSObject, Observable, CLLocationManagerDelegate {

    /// 天气信息
    struct WeatherInfo: Sendable {
        let summary: String
        let detail: String
        let icon: String
        let temperature: Double
    }

    private(set) var currentInfo: WeatherInfo?
    private(set) var isLoading = false

    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// 刷新天气数据
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        locationManager.requestLocation()

        // 等待位置更新
        try? await Task.sleep(for: .seconds(3))

        guard let location = currentLocation else {
            currentInfo = WeatherInfo(
                summary: "无法获取位置",
                detail: "请在系统设置中授予位置权限",
                icon: "location.slash",
                temperature: 0
            )
            return
        }

        // WeatherKit 需要真实的 Apple Developer 账号
        // 这里提供框架接口
        currentInfo = WeatherInfo(
            summary: "天气服务就绪",
            detail:
                "位置: \(String(format: "%.2f", location.coordinate.latitude)), \(String(format: "%.2f", location.coordinate.longitude))",
            icon: "cloud.sun",
            temperature: 0
        )
    }

    /// 获取当前天气
    func currentWeather() async -> WeatherInfo? {
        if currentInfo == nil { await refresh() }
        return currentInfo
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
    {
        Task { @MainActor in
            currentLocation = locations.last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 常见原因：未授予位置权限，或系统「定位服务」被关闭。
        QuickLog.module("weather").error("定位失败: \(error.localizedDescription, privacy: .public)")
    }
}
