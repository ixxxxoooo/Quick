// AIConfig.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 宿主级 AI 生成参数
///
/// 服务商、Key、模型是多份的，见 `AIProvider` / `AIProviderStore`；
/// 这里只放「所有服务商共用」的生成参数。
public struct AIConfig: Sendable, Equatable {

    public var maxTokens: Int
    public var temperature: Double

    public static let defaultMaxTokens = 4096
    public static let minMaxTokens = 256
    public static let maxMaxTokens = 32768
    public static let defaultTemperature = 0.7
    public static let maxTemperature = 2.0

    public init(
        maxTokens: Int = AIConfig.defaultMaxTokens,
        temperature: Double = AIConfig.defaultTemperature
    ) {
        self.maxTokens = AIConfig.clampedMaxTokens(maxTokens)
        self.temperature = AIConfig.clampedTemperature(temperature)
    }

    /// 从偏好读出；没设置过用默认，越界值夹回合法范围
    public static func load(from defaults: UserDefaults = .standard) -> AIConfig {
        AIConfig(
            maxTokens: defaults.object(forKey: SettingsKey.AI.maxTokens) as? Int ?? defaultMaxTokens,
            temperature: defaults.object(forKey: SettingsKey.AI.temperature) as? Double
                ?? defaultTemperature
        )
    }

    public static func clampedMaxTokens(_ value: Int) -> Int {
        min(maxMaxTokens, max(minMaxTokens, value))
    }

    public static func clampedTemperature(_ value: Double) -> Double {
        min(maxTemperature, max(0, value))
    }
}
