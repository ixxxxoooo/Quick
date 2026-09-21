// CalcPreferences.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 计算结果要用的显示选项
///
/// 纯数据：引擎按它格式化，至于这些值从哪个键读出来、用户什么时候改的，
/// 引擎不关心 —— 这样引擎仍然是没有环境依赖的纯计算。
struct CalcDisplayOptions: Sendable, Equatable {

    /// 最多保留的小数位数（设置页的「完整精度」就是 10）
    let maximumFractionDigits: Int

    /// 是否插入千分位分隔符
    let usesGroupingSeparator: Bool

    /// 从未设置过时设置页显示的档位：4 位小数 + 千分位
    static let `default` = CalcDisplayOptions(
        maximumFractionDigits: CalcPreferences.defaultPrecision,
        usesGroupingSeparator: true
    )
}

/// 计算器偏好的读取与映射
///
/// 读键的动作发生在**每次计算与每次回车**时，不是在插件 init 里读一次：
/// 设置页可以在应用运行期间随时改，捕获一次的话用户就会看到「改了没反应」。
enum CalcPreferences {

    /// 设置页里可选的档位
    static let precisionChoices = [2, 4, 6, 10]

    /// 设置页在「从未设置过」时的默认档位
    static let defaultPrecision = 4

    /// 把存储值映射成合法的精度
    ///
    /// `UserDefaults.integer(forKey:)` 对没写过的键返回 0，被删掉或手改过的值也可能是任意整数，
    /// 所以非法输入一律回落到设置页显示的默认档 —— 不能让一个越界值把结果显示成整数。
    static func precision(storedValue: Int) -> Int {
        precisionChoices.contains(storedValue) ? storedValue : defaultPrecision
    }

    /// 当前的小数与分隔符设置
    static func displayOptions(defaults: UserDefaults = .standard) -> CalcDisplayOptions {
        CalcDisplayOptions(
            maximumFractionDigits: precision(
                storedValue: defaults.integer(forKey: PluginSettingKey.Calculator.precision)),
            // 没写过这个键时要按设置页显示的「开」处理，不能直接用 bool(forKey:)（它把未设置读成 false）
            usesGroupingSeparator: boolValue(
                forKey: PluginSettingKey.Calculator.useGroupingSeparator,
                fallback: true,
                defaults: defaults
            )
        )
    }

    /// 回车确认后是否自动复制结果
    static func autoCopy(defaults: UserDefaults = .standard) -> Bool {
        boolValue(
            forKey: PluginSettingKey.Calculator.autoCopy,
            fallback: false,
            defaults: defaults
        )
    }

    /// 读布尔值，未设置过（`object` 为 nil）时返回 `fallback`
    private static func boolValue(
        forKey key: String,
        fallback: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }
}

/// 数字的显示格式化
///
/// 单独抽出来是因为「小数位数」和「千分位」两个开关都作用在这一步，而它是纯函数 ——
/// 不这样拆的话，两个开关的效果只能用跑起来的 UI 才看得见。
enum CalcFormatting {

    /// 把计算结果格式化成展示字符串
    ///
    /// 整数也走同一个格式化器：以前整数走 `String(format: "%.0f")` 绕过了它，
    /// 于是千分位开关对 1000000 这种整数完全无效，而设置页承诺的恰恰就是整数场景。
    static func string(from value: Double, options: CalcDisplayOptions) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = options.maximumFractionDigits
        formatter.minimumFractionDigits = 0
        // 必须写在 numberStyle 之后：`.decimal` 样式会把 usesGroupingSeparator 重置为 true
        formatter.usesGroupingSeparator = options.usesGroupingSeparator
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
