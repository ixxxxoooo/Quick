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

    /// 触发词
    private static let triggers = ["天气", "weather", "温度", "预报"]

    public init() {}

    /// 纯查询：**这里不取位置。**
    ///
    /// `searchItems` 每次按键（防抖后）都会跑，而取位置最长要 8 秒；
    /// 聚合搜索又要等所有模块都返回，所以在这里取位置会把**整批**结果卡住。
    /// 需要取的时候由用户点这一条去触发 —— 那也是定位权限该被申请的时机。
    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggers) else { return [] }

        if let info = service.currentInfo {
            return [
                SearchableItem(
                    id: "weather.current",
                    moduleID: Self.id,
                    title: info.summary,
                    subtitle: info.detail,
                    icon: info.icon,
                    relevance: 0.6,
                    action: { [weak self] in self?.fetchAndReport() }
                )
            ]
        }

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

        case .locationUnavailable, nil:
            // 还没取过，或上次没取到：给一条会去取的动作。
            // 这一条是天气模块唯一会发起定位请求的地方。
            return [
                SearchableItem(
                    id: "weather.fetch",
                    moduleID: Self.id,
                    title: "查看当前天气",
                    subtitle: "需要获取一次大致位置（公里级）",
                    icon: "cloud.sun",
                    relevance: 0.6,
                    action: { [weak self] in self?.fetchAndReport() }
                )
            ]
        }
    }

    /// 取一次天气，并把结果通过 HUD 报出来
    ///
    /// 面板目前还没有承载模块视图，所以结果走 HUD 而不是一个天气页面 ——
    /// 至少用户点了之后能看到东西，而不是面板一关什么都没发生。
    private func fetchAndReport() {
        Task { @MainActor in
            await service.refresh()
            if let info = service.currentInfo {
                EventBus.shared.post(ShowHUDEvent(message: info.detail, tone: .info))
            } else {
                EventBus.shared.post(ShowHUDEvent(message: "暂时拿不到位置，稍后重试", tone: .warning))
            }
            EventBus.shared.post(HidePaletteEvent())
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
