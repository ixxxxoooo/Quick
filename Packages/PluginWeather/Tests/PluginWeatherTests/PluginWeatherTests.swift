// PluginWeatherTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginWeather

@Suite("坐标格式化")
struct WeatherFormattingTests {

    /// 两位小数对应公里级定位精度，多一位都是虚假的精确感
    @Test("经纬度按两位小数拼成位置行")
    func formatsCoordinate() {
        #expect(
            WeatherFormatting.locationDetail(latitude: 39.9042, longitude: 116.4074) == "位置: 39.90, 116.41")
        #expect(WeatherFormatting.locationDetail(latitude: 12.3456, longitude: -7.8912) == "位置: 12.35, -7.89")
        #expect(WeatherFormatting.locationDetail(latitude: 0, longitude: 0) == "位置: 0.00, 0.00")
    }

    /// 负值必须保留符号，南纬/西经丢掉负号会把用户指到地球另一边
    @Test("负坐标保留负号，且不补零成整数")
    func formatsNegativeCoordinate() {
        #expect(
            WeatherFormatting.locationDetail(latitude: -33.8688, longitude: 151.2093) == "位置: -33.87, 151.21")
        #expect(WeatherFormatting.locationDetail(latitude: -0.5, longitude: -0.25) == "位置: -0.50, -0.25")
    }
}

@Suite("占位天气信息")
struct WeatherInfoTests {

    /// WeatherKit 未接入，当前行为就是「一句摘要 + 坐标 + 固定图标 + 温度 0」。
    /// 钉住它是为了让接入 WeatherKit 的那次改动必须同步更新这里。
    @Test("locationReady 产出固定的占位内容")
    func locationReadyPlaceholder() {
        let info = WeatherInfo.locationReady(latitude: 39.9042, longitude: 116.4074)

        #expect(info.summary == "天气服务就绪")
        #expect(info.detail == "位置: 39.90, 116.41")
        #expect(info.icon == "cloud.sun")
        #expect(info.temperature == 0)
    }
}

@Suite("定位授权状态")
struct WeatherAuthorizationTests {

    /// 只有授权成功才能去取位置；其余三档都必须留在本地并给提示
    @Test("只有 authorized 算已授权")
    func isAuthorized() {
        #expect(WeatherAuthorization.authorized.isAuthorized)
        #expect(!WeatherAuthorization.notDetermined.isAuthorized)
        #expect(!WeatherAuthorization.denied.isAuthorized)
    }

    /// 原因决定给用户哪条结果：只有「还没问过」才能弹权限框，
    /// 拒绝过再去申请只会被系统直接忽略
    @Test("未授权原因按三档映射")
    func unavailableReason() {
        #expect(WeatherAuthorization.notDetermined.unavailableReason == .needsPermission)
        #expect(WeatherAuthorization.denied.unavailableReason == .permissionDenied)
        #expect(WeatherAuthorization.authorized.unavailableReason == nil)
    }
}

@MainActor
@Suite("天气插件契约")
struct WeatherPluginTests {

    @Test("元数据符合插件约定")
    func metadata() {
        #expect(WeatherPlugin.id == "weather")
        #expect(WeatherPlugin.id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
        #expect(WeatherPlugin.name == "天气")
        #expect(WeatherPlugin.icon == "cloud.sun")
        #expect(WeatherPlugin.triggerWords == ["天气", "weather", "温度", "预报"])
    }

    /// 全新实例既没有数据也没有「不可用原因」，走的是「还没取过」那条 ——
    /// 它只返回一条会去取位置的入口，本身不碰定位（这是插件的不变量）
    @Test("首次查询返回一条取天气的入口")
    func firstQueryReturnsFetchEntry() async {
        let plugin = WeatherPlugin()
        let items = await plugin.searchItems(query: "天气")

        #expect(items.count == 1)
        #expect(items.first?.id == "weather.fetch")
        #expect(items.first?.pluginID == WeatherPlugin.id)
        #expect(items.first?.title == "查看当前天气")
        #expect(items.first?.relevance == 0.6)
    }

    @Test("中英文触发词都能命中")
    func triggerWordsMatch() async {
        let plugin = WeatherPlugin()
        for query in ["天气", "weather", "温度", "预报"] {
            let items = await plugin.searchItems(query: query)
            #expect(items.count == 1, "\(query) 应当命中")
            #expect(items.first?.pluginID == WeatherPlugin.id)
        }
    }

    /// 触发词按整词匹配：`weather` 里的子串不该放行无关查询
    @Test("未命中触发词时不返回任何结果")
    func unrelatedQueryReturnsNothing() async {
        let plugin = WeatherPlugin()
        #expect(await plugin.searchItems(query: "clipboard").isEmpty)
        #expect(await plugin.searchItems(query: "日历").isEmpty)
        #expect(await plugin.searchItems(query: "").isEmpty)
    }
}
