// WeatherModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 天气预报模块
///
/// 使用 WeatherKit 获取当前位置的天气信息。
///
/// **定位权限只在用户主动查看天气时申请**，启动时不碰定位 ——
/// 策略与原因见 `WeatherService` 的类型文档。
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

        // 用户已经在找天气了，这时拉数据是合理的上下文。
        // refresh() 不会弹权限框：未授权时它只记录原因。
        await service.refresh()

        if let info = service.currentInfo {
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

        // 拿不到数据时给一条可操作的入口，而不是一句「失败」。
        switch service.unavailableReason {
        case .needsPermission:
            return [
                SearchableItem(
                    id: "weather.request-permission",
                    moduleID: Self.id,
                    title: "授予定位权限以显示天气",
                    subtitle: "只在你主动查看天气时申请，不会在启动时弹出",
                    icon: "location.circle",
                    relevance: 0.6,
                    action: { [weak self] in
                        self?.service.requestAuthorization()
                        EventBus.shared.post(HidePaletteEvent())
                    }
                )
            ]

        case .permissionDenied:
            return [
                SearchableItem(
                    id: "weather.permission-denied",
                    moduleID: Self.id,
                    title: "定位权限已被拒绝",
                    subtitle: "到「系统设置 › 隐私与安全性 › 定位服务」中开启，然后重试",
                    icon: "location.slash",
                    relevance: 0.6,
                    action: { [weak self] in
                        self?.log.notice("用户从搜索结果打开了定位服务设置")
                        PermissionService().openLocationSettings()
                        EventBus.shared.post(HidePaletteEvent())
                    }
                )
            ]

        case .locationUnavailable:
            return [
                SearchableItem(
                    id: "weather.location-unavailable",
                    moduleID: Self.id,
                    title: "暂时拿不到位置",
                    subtitle: "已授权但系统未返回位置，稍后重试",
                    icon: "location.slash",
                    relevance: 0.5,
                    action: {}
                )
            ]

        case nil:
            return []
        }
    }

    public func makeView() -> AnyView {
        AnyView(WeatherView(service: service))
    }

    public func activate() {
        // 不在激活时申请定位，也不在激活时刷新天气：
        // 那会让每次启动都弹系统权限框，而且用户还没表达要看天气的意图。
        log.notice("模块已激活，天气按需获取（启动时不申请定位权限）")
    }

    public func deactivate() {
        log.notice("模块已停用")
    }
}
