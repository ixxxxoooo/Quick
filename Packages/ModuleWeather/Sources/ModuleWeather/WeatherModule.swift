// WeatherModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI
import WeatherKit

/// 天气预报模块
///
/// 使用 WeatherKit 获取当前位置的天气信息。
@MainActor
public final class WeatherModule: QuickModule {

    public static let id = "weather"
    public static let name = "天气"
    public static let icon = "cloud.sun"

    public var isEnabled = true

    private let log = QuickLog.module(WeatherModule.id)

    private let service = WeatherService()

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        let triggers = ["天气", "weather", "温度", "预报"]
        guard triggers.contains(where: { query.lowercased().contains($0) }) else { return [] }

        let info = await service.currentWeather()
        guard let info else { return [] }

        return [
            SearchableItem(
                id: "weather.current",
                moduleID: Self.id,
                title: info.summary,
                subtitle: info.detail,
                icon: info.icon,
                relevance: 0.6,
                action: {}
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(WeatherView(service: service))
    }

    public func activate() {
        Task { await service.refresh() }
        log.notice("模块已激活，已发起天气刷新任务")
    }

    public func deactivate() {
        log.notice("模块已停用")
    }
}
