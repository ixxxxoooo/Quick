// CalcSettingsTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginCalculator

// MARK: - 纯格式化

@Suite("计算结果格式化")
struct CalcFormattingTests {

    /// 千分位开关作用在格式化这一步，所以两个状态的输出必须不同 ——
    /// 整数以前走 `String(format: "%.0f")`，绕过格式化器，开关对它完全无效
    @Test("千分位开关改变整数与大数的显示")
    func groupingSeparatorChangesIntegers() {
        let grouped = CalcFormatting.string(from: 1_000_000, options: .default)
        let plain = CalcFormatting.string(
            from: 1_000_000,
            options: CalcDisplayOptions(maximumFractionDigits: 4, usesGroupingSeparator: false)
        )

        // 分隔符本身随地区变（德语是 1.000.000），断言「插入了当前地区的分隔符」而不是写死逗号
        let separator = Locale.current.groupingSeparator ?? ","
        #expect(grouped == "1\(separator)000\(separator)000")
        #expect(plain == "1000000")
        #expect(grouped != plain)
    }

    @Test("小数位数改变保留的位数，并且四舍五入")
    func precisionChangesFractionDigits() {
        let two = CalcDisplayOptions(maximumFractionDigits: 2, usesGroupingSeparator: true)
        let six = CalcDisplayOptions(maximumFractionDigits: 6, usesGroupingSeparator: true)

        #expect(CalcFormatting.string(from: 1.0 / 3.0, options: two) == "0.33")
        #expect(CalcFormatting.string(from: 1.0 / 3.0, options: six) == "0.333333")
        #expect(CalcFormatting.string(from: 2.0 / 3.0, options: two) == "0.67")
        #expect(CalcFormatting.string(from: 2.0 / 3.0, options: six) == "0.666667")
        // 整数不补零到固定位数，也不带小数点
        #expect(CalcFormatting.string(from: 4, options: six) == "4")
    }

    @Test("单位换算的带单位结果同样受两个开关影响")
    @MainActor
    func unitConversionKeepsTheSameFormatting() {
        let options = CalcDisplayOptions(maximumFractionDigits: 2, usesGroupingSeparator: false)
        let result = CalcEngine().evaluate("100 km to mi", options: options)

        // 100 km ≈ 62.137 mi，2 位小数下是 62.14
        #expect(result?.formatted == "62.14 mi")
    }
}

// MARK: - 偏好读取

@Suite("计算器偏好读取")
struct CalcPreferencesTests {

    /// 独立 suite：读映射的用例不碰真实偏好，也就不会给别的用例留下残留
    private static func scratchDefaults() -> UserDefaults? {
        UserDefaults(suiteName: "com.ixxxxoooo.quick.tests.calculator.\(UUID().uuidString)")
    }

    @Test("精度只认设置页给出的四档，其余一律回落到 4")
    func precisionMapping() {
        for choice in CalcPreferences.precisionChoices {
            #expect(CalcPreferences.precision(storedValue: choice) == choice)
        }
        // 没写过（integer(forKey:) 返回 0）与手改坏的值
        #expect(CalcPreferences.precision(storedValue: 0) == 4)
        #expect(CalcPreferences.precision(storedValue: 3) == 4)
        #expect(CalcPreferences.precision(storedValue: -1) == 4)
        #expect(
            CalcDisplayOptions.default
                == CalcDisplayOptions(maximumFractionDigits: 4, usesGroupingSeparator: true))
    }

    @Test("未设置过时就是设置页显示的档位：4 位 + 千分位")
    func emptyDefaultsFallBackToThePaneDefaults() throws {
        let defaults = try #require(Self.scratchDefaults())

        #expect(CalcPreferences.displayOptions(defaults: defaults) == .default)
        #expect(CalcPreferences.autoCopy(defaults: defaults) == false)
    }

    @Test("小数位数与千分位跟着键走")
    func displayOptionsFollowStoredValues() throws {
        let defaults = try #require(Self.scratchDefaults())

        defaults.set(6, forKey: PluginSettingKey.Calculator.precision)
        defaults.set(false, forKey: PluginSettingKey.Calculator.useGroupingSeparator)
        #expect(
            CalcPreferences.displayOptions(defaults: defaults)
                == CalcDisplayOptions(maximumFractionDigits: 6, usesGroupingSeparator: false))

        defaults.set(2, forKey: PluginSettingKey.Calculator.precision)
        defaults.set(true, forKey: PluginSettingKey.Calculator.useGroupingSeparator)
        #expect(
            CalcPreferences.displayOptions(defaults: defaults)
                == CalcDisplayOptions(maximumFractionDigits: 2, usesGroupingSeparator: true))
    }

    @Test("自动复制跟着开关走")
    func autoCopyFollowsTheToggle() throws {
        let defaults = try #require(Self.scratchDefaults())

        // 设置页默认关，未设置过就不能复制
        #expect(!CalcPreferences.autoCopy(defaults: defaults))
        defaults.set(true, forKey: PluginSettingKey.Calculator.autoCopy)
        #expect(CalcPreferences.autoCopy(defaults: defaults))
        defaults.set(false, forKey: PluginSettingKey.Calculator.autoCopy)
        #expect(!CalcPreferences.autoCopy(defaults: defaults))
    }
}

// MARK: - 插件接线

/// 插件读的是标准偏好存储，用例也只能写标准存储 —— 换成独立 suite 就测不到接线了。
/// 标准存储是进程共享的，所以用例必须串行并自己收尾（见 `withStandardDefaults`）。
@MainActor
@Suite("计算器插件的设置接线", .serialized)
struct CalculatorPluginSettingsTests {

    private static let touchedKeys = [
        PluginSettingKey.Calculator.precision,
        PluginSettingKey.Calculator.useGroupingSeparator,
        PluginSettingKey.Calculator.autoCopy
    ]

    /// 跑完把这三个键的旧值原样放回去，不让用例互相污染，也不留在真实偏好里
    private static func withStandardDefaults(_ body: () async throws -> Void) async throws {
        var saved: [String: Any] = [:]
        for key in touchedKeys {
            saved[key] = UserDefaults.standard.object(forKey: key)
        }
        defer {
            for key in touchedKeys {
                if let previous = saved[key] {
                    UserDefaults.standard.set(previous, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        try await body()
    }

    @Test("小数位数真的改变了结果项标题")
    func precisionReachesTheResultTitle() async throws {
        try await Self.withStandardDefaults {
            let plugin = CalculatorPlugin()

            UserDefaults.standard.set(2, forKey: PluginSettingKey.Calculator.precision)
            #expect(await plugin.searchItems(query: "2/3").first?.title == "0.67")

            UserDefaults.standard.set(6, forKey: PluginSettingKey.Calculator.precision)
            #expect(await plugin.searchItems(query: "2/3").first?.title == "0.666667")
        }
    }

    @Test("没设置过时按设置页显示的 4 位")
    func unsetPrecisionUsesThePaneDefault() async throws {
        try await Self.withStandardDefaults {
            UserDefaults.standard.removeObject(forKey: PluginSettingKey.Calculator.precision)

            #expect(await CalculatorPlugin().searchItems(query: "2/3").first?.title == "0.6667")
        }
    }

    @Test("千分位开关真的改变了结果项标题")
    func groupingSeparatorReachesTheResultTitle() async throws {
        try await Self.withStandardDefaults {
            let plugin = CalculatorPlugin()
            let separator = Locale.current.groupingSeparator ?? ","

            UserDefaults.standard.set(false, forKey: PluginSettingKey.Calculator.useGroupingSeparator)
            #expect(await plugin.searchItems(query: "1000000*1").first?.title == "1000000")

            UserDefaults.standard.set(true, forKey: PluginSettingKey.Calculator.useGroupingSeparator)
            #expect(
                await plugin.searchItems(query: "1000000*1").first?.title
                    == "1\(separator)000\(separator)000")
        }
    }

    @Test("回车后是否落到剪贴板由开关决定")
    func autoCopyDecidesWhetherEnterCopies() async throws {
        try await Self.withStandardDefaults {
            var copied: [String] = []
            let subscription = EventBus.shared.on(CopyToClipboardEvent.self) { copied.append($0.text) }
            defer { subscription.cancel() }

            UserDefaults.standard.set(true, forKey: PluginSettingKey.Calculator.autoCopy)
            let items = await CalculatorPlugin().searchItems(query: "6*7")
            let copying = try #require(items.first)
            #expect(copying.shortcutHint == "⏎ 复制")
            copying.action()
            #expect(copied == ["42"])

            // 关掉之后同一个动作不能再往剪贴板里写东西
            UserDefaults.standard.set(false, forKey: PluginSettingKey.Calculator.autoCopy)
            let silentItems = await CalculatorPlugin().searchItems(query: "6*7")
            let silent = try #require(silentItems.first)
            #expect(silent.shortcutHint == "⏎ 完成")
            silent.action()
            #expect(copied == ["42"])
        }
    }
}
