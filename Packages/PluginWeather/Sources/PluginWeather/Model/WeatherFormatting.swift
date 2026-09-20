// WeatherFormatting.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 天气结果的文本格式化
///
/// 全部是纯函数：不碰定位、不碰网络、不依赖任何框架类型，因此可以独立测试。
/// 格式化一旦写错（例如经纬度反过来、精度不对），用户看到的是一条看似正常的
/// 错误信息，比崩溃更难发现 —— 所以它值得被钉住。
enum WeatherFormatting {

    /// 把坐标格式化成用户可读的「位置」行
    ///
    /// 两位小数对应公里级定位精度：定位本身只要到公里级（见 `WeatherService`），
    /// 多显示几位只会给出虚假的精确感。
    static func locationDetail(latitude: Double, longitude: Double) -> String {
        "位置: \(String(format: "%.2f", latitude)), \(String(format: "%.2f", longitude))"
    }
}
