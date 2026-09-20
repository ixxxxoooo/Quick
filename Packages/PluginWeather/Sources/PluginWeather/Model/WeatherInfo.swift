// WeatherInfo.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 天气信息
///
/// 纯值类型，只描述「要显示什么」。放在 Model 层是因为它必须能被独立编译和测试：
/// 一旦它落在 `WeatherService` 里，取它的测试就被迫连带 CoreLocation 一起启动。
struct WeatherInfo: Sendable {
    let summary: String
    let detail: String
    let icon: String
    let temperature: Double
}

extension WeatherInfo {

    /// 已拿到位置时的占位内容
    ///
    /// WeatherKit 尚未接入（需要真实 Apple Developer 账号），所以这里只回一句
    /// 摘要和坐标。把这段纯逻辑放在 Model 层，是为了让「占位内容长什么样」能被
    /// 测试钉住 —— 接入 WeatherKit 时它会整段被替换，届时测试会立刻失败并提醒
    /// 我们同步更新。
    static func locationReady(latitude: Double, longitude: Double) -> WeatherInfo {
        WeatherInfo(
            summary: "天气服务就绪",
            detail: WeatherFormatting.locationDetail(latitude: latitude, longitude: longitude),
            icon: "cloud.sun",
            temperature: 0
        )
    }
}
