// UnitConversionTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginCalculator

/// 固定汇率样本：测试不依赖当天行情，也不联网
private func sampleRates() -> CurrencyRates {
    var rates: [String: Double] = ["USD": 1, "CNY": 7.2, "EUR": 0.9, "JPY": 150, "GBP": 0.8]
    // 解析要求至少 20 个币种，样本里补齐，保持与真实响应同构
    for index in 0..<20 { rates["X\(index)A"] = Double(index + 1) }
    return CurrencyRates(perUSD: rates, updatedAt: Date(timeIntervalSince1970: 1_790_000_000))
}

private let plain = CalcDisplayOptions(maximumFractionDigits: 4, usesGroupingSeparator: false)

@Suite("单位换算")
struct UnitConversionTests {

    private let engine = CalcEngine()

    @Test("常用单位互换", arguments: [
        ("1 km to m", "1000 m"),
        ("1 mi to km", "1.6093 km"),
        ("5 斤 转 kg", "2.5 kg"),
        ("2 两 to g", "100 g"),
        ("1 gal to l", "3.7854 l"),
        ("1 h to min", "60 min"),
        ("1 day to h", "24 h"),
        ("1 gb to mb", "1000 mb"),
        ("1 gib to mib", "1024 mib"),
        ("36 km/h to m/s", "10 m/s"),
        ("1 公顷 to m2", "10000 m2"),
        ("1 里 to m", "500 m"),
    ])
    func convertsCommonUnits(input: String, expected: String) {
        #expect(engine.evaluate(input, options: plain)?.formatted == expected)
    }

    @Test("单位名里带分隔词也能解析：in 是英寸，min 是分钟")
    func unitNamesContainingSeparatorWords() {
        #expect(engine.evaluate("1 in to cm", options: plain)?.formatted == "2.54 cm")
        #expect(engine.evaluate("1 ft in in", options: plain)?.formatted == "12 in")
        #expect(engine.evaluate("5 min to s", options: plain)?.formatted == "300 s")
        #expect(engine.evaluate("2 h in min", options: plain)?.formatted == "120 min")
    }

    @Test("中文分隔词无需空格；千分位输入")
    func chineseSeparatorsAndGroupedInput() {
        #expect(engine.evaluate("1000m转km", options: plain)?.formatted == "1 km")
        #expect(engine.evaluate("1,500 g to kg", options: plain)?.formatted == "1.5 kg")
        #expect(engine.evaluate("100 km -> mi", options: plain)?.formatted == "62.1371 mi")
    }

    @Test("温度：摄氏、华氏、开尔文互换")
    func temperatures() {
        #expect(engine.evaluate("100 c to f", options: plain)?.formatted == "212°F")
        #expect(engine.evaluate("32 f to c", options: plain)?.formatted == "0°C")
        #expect(engine.evaluate("0 c to k", options: plain)?.formatted == "273.15K")
        #expect(engine.evaluate("0 k to c", options: plain)?.formatted == "-273.15°C")
    }

    @Test("不同类别之间不能换算，也不会崩溃")
    func mismatchedCategoriesFail() {
        #expect(engine.evaluate("1 km to kg", options: plain) == nil)
        #expect(engine.evaluate("1 h to m", options: plain) == nil)
        #expect(engine.evaluate("1 foo to bar", options: plain) == nil)
        #expect(engine.evaluate("km to m", options: plain) == nil)
        #expect(engine.evaluate("1 km to", options: plain) == nil)
    }

    @Test("搜索闸门：普通词里含 to / in 不再被当成换算")
    func gateIsNotFooledBySubstrings() {
        let engine = CalcEngine()
        for word in ["photoshop", "settings", "terminal", "stop", "留言", "翻译", "kingdom"] {
            #expect(!engine.looksLikeExpression(word), "\(word) 不该被当成表达式")
        }
        #expect(engine.looksLikeExpression("100 km to mi"))
        #expect(engine.looksLikeExpression("1000m转km"))
        #expect(engine.looksLikeExpression("1+1"))
    }
}

@Suite("货币换算")
struct CurrencyConversionTests {

    private func engine(rates: CurrencyRates? = sampleRates()) -> CalcEngine {
        CalcEngine(rates: CurrencyRateCache(suiteName: "calc.currency.\(UUID().uuidString)", seed: rates))
    }

    @Test("代码与中文名都能识别")
    func codesAndChineseNames() {
        let engine = engine()
        #expect(engine.evaluate("100 usd to cny", options: plain)?.formatted == "720 CNY")
        #expect(engine.evaluate("50 美元转人民币", options: plain)?.formatted == "360 CNY")
        #expect(engine.evaluate("720 CNY in USD", options: plain)?.formatted == "100 USD")
        #expect(engine.evaluate("1500 jpy to eur", options: plain)?.formatted == "9 EUR")
    }

    @Test("结果带汇率更新日期的附注")
    func carriesFreshnessNote() {
        let note = engine().evaluate("1 usd to cny", options: plain)?.note
        #expect(note?.hasPrefix("汇率更新于") == true)
    }

    @Test("没有汇率时货币换算不给结果，不编数")
    func noRatesNoResult() {
        #expect(engine(rates: nil).evaluate("100 usd to cny", options: plain) == nil)
    }

    @Test("未知币种返回 nil")
    func unknownCurrency() {
        #expect(engine().evaluate("100 usd to zzz", options: plain) == nil)
    }

    @Test("解析真实形态的响应；非成功或币种过少的响应被拒绝")
    func parsesPayload() throws {
        var rates: [String: Double] = ["USD": 1]
        for index in 0..<30 { rates["C\(index)\(index)"] = 1.5 }
        let good = try JSONSerialization.data(withJSONObject: [
            "result": "success", "time_last_update_unix": 1_790_000_000, "rates": rates,
        ])
        let parsed = CurrencyRates.parse(good)
        #expect(parsed?.perUSD["USD"] == 1)
        #expect(parsed?.updatedAt == Date(timeIntervalSince1970: 1_790_000_000))

        let failed = try JSONSerialization.data(withJSONObject: ["result": "error", "rates": rates])
        #expect(CurrencyRates.parse(failed) == nil)
        let tooFew = try JSONSerialization.data(withJSONObject: ["result": "success", "rates": ["USD": 1.0]])
        #expect(CurrencyRates.parse(tooFew) == nil)
        #expect(CurrencyRates.parse(Data("<html>captive portal</html>".utf8)) == nil)
    }

    @Test("缓存：新鲜时不联网，过期才拉，失败保留旧值，成功后落盘")
    func cacheRefreshPolicy() async throws {
        let suite = "calc.cache.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let stale = CurrencyRates(perUSD: sampleRates().perUSD, updatedAt: Date(timeIntervalSince1970: 1_000))
        let cache = CurrencyRateCache(suiteName: suite, seed: stale)

        var rates: [String: Double] = ["USD": 1]
        for index in 0..<30 { rates["C\(index)\(index)"] = 2 }
        let payload = try JSONSerialization.data(withJSONObject: [
            "result": "success", "time_last_update_unix": 2_000_000_000, "rates": rates,
        ])

        // 过期 + 拉取失败：旧值保留
        await cache.refreshIfNeeded(now: Date(timeIntervalSince1970: 2_000_000_100)) { throw URLError(.notConnectedToInternet) }
        #expect(cache.current?.updatedAt == stale.updatedAt)

        // 过期 + 拉取成功：更新并落盘
        await cache.refreshIfNeeded(now: Date(timeIntervalSince1970: 2_000_000_100)) { payload }
        #expect(cache.current?.updatedAt == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(defaults.data(forKey: CurrencyRateCache.storageKey) != nil)

        // 新鲜：不应再取
        await cache.refreshIfNeeded(now: Date(timeIntervalSince1970: 2_000_000_200)) {
            Issue.record("缓存新鲜时不该联网")
            return payload
        }

        // 重启后从存储读回
        let reloaded = CurrencyRateCache(suiteName: suite)
        #expect(reloaded.current?.updatedAt == Date(timeIntervalSince1970: 2_000_000_000))
    }

    @Test("设置：缺省为关（离线优先，用户主动开启才联网）")
    func onlineSettingDefaultsOff() {
        let suite = UserDefaults(suiteName: "calc.pref.\(UUID().uuidString)")!
        #expect(!CalcPreferences.onlineCurrencyRates(defaults: suite))
        suite.set(true, forKey: "calculator.onlineCurrencyRates")
        #expect(CalcPreferences.onlineCurrencyRates(defaults: suite))
    }
}
