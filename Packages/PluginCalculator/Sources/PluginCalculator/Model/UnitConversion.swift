// UnitConversion.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 单位换算（纯逻辑）
///
/// 自己维护「别名 → 类别 + 到基准单位的系数」的表，而不是用 Foundation 的 `Measurement`：
/// 后者没有斤、两、里、尺这些中文常用单位，也没法按别名（`km/h`、`平方米`）查。
/// 温度不是线性换算，单独走 `convertTemperature`；货币在 `CurrencyRates`。
nonisolated enum UnitConversion {

    /// 单位类别：只有同类别之间才能换算
    enum Category: Sendable {
        case length, mass, volume, area, speed, time, data
    }

    private struct Entry {
        let category: Category
        /// 1 个该单位 = 多少基准单位（长度 m、质量 g、体积 mL、面积 m²、速度 m/s、时间 s、数据 B）
        let factor: Double
    }

    /// 别名一律小写
    private static let table: [String: Entry] = {
        var table: [String: Entry] = [:]
        func add(_ category: Category, _ factor: Double, _ aliases: String...) {
            for alias in aliases { table[alias] = Entry(category: category, factor: factor) }
        }
        // 长度（基准：米）
        add(.length, 1000, "km", "千米", "公里", "kilometer", "kilometers")
        add(.length, 1, "m", "米", "meter", "meters")
        add(.length, 0.1, "dm", "分米")
        add(.length, 0.01, "cm", "厘米", "公分")
        add(.length, 0.001, "mm", "毫米")
        add(.length, 1609.344, "mi", "mile", "miles", "英里")
        add(.length, 0.9144, "yd", "yard", "yards", "码")
        add(.length, 0.3048, "ft", "foot", "feet", "英尺")
        add(.length, 0.0254, "in", "inch", "inches", "英寸")
        add(.length, 1852, "nmi", "海里")
        add(.length, 500, "里", "市里")
        add(.length, 1.0 / 3.0, "尺", "市尺")
        add(.length, 1.0 / 30.0, "寸", "市寸")
        // 质量（基准：克）
        add(.mass, 1_000_000, "t", "吨", "tonne", "tonnes")
        add(.mass, 1000, "kg", "千克", "公斤", "kilogram", "kilograms")
        add(.mass, 1, "g", "克", "gram", "grams")
        add(.mass, 0.001, "mg", "毫克")
        add(.mass, 453.59237, "lb", "lbs", "pound", "pounds", "磅")
        add(.mass, 28.349523125, "oz", "ounce", "ounces", "盎司")
        add(.mass, 500, "斤", "市斤")
        add(.mass, 50, "两", "市两")
        // 体积（基准：毫升）
        add(.volume, 1000, "l", "升", "liter", "liters", "litre")
        add(.volume, 1, "ml", "毫升")
        add(.volume, 3785.411784, "gal", "gallon", "gallons", "加仑")
        add(.volume, 946.352946, "qt", "quart", "quarts")
        add(.volume, 473.176473, "pt", "pint", "pints")
        add(.volume, 29.5735295625, "floz", "fl oz", "液量盎司")
        add(.volume, 236.5882365, "cup", "cups", "杯")
        // 面积（基准：平方米）
        add(.area, 1_000_000, "km2", "km²", "平方公里", "平方千米")
        add(.area, 1, "m2", "m²", "平方米")
        add(.area, 0.0001, "cm2", "cm²", "平方厘米")
        add(.area, 10_000, "ha", "hectare", "hectares", "公顷")
        add(.area, 4046.8564224, "acre", "acres", "英亩")
        add(.area, 0.09290304, "ft2", "ft²", "sqft", "平方英尺")
        add(.area, 666.6666666667, "亩")
        // 速度（基准：米/秒）
        add(.speed, 1, "m/s", "米每秒")
        add(.speed, 1.0 / 3.6, "km/h", "kmh", "kph", "公里每小时", "千米每小时", "公里/小时")
        add(.speed, 0.44704, "mph", "英里每小时")
        add(.speed, 0.514444444, "kn", "knot", "knots", "节")
        // 时间（基准：秒）
        add(.time, 604_800, "w", "week", "weeks", "周", "星期")
        add(.time, 86_400, "d", "day", "days", "天", "日")
        add(.time, 3600, "h", "hr", "hour", "hours", "小时")
        add(.time, 60, "min", "mins", "minute", "minutes", "分钟", "分")
        add(.time, 1, "s", "sec", "second", "seconds", "秒")
        add(.time, 0.001, "ms", "毫秒")
        // 数据量（基准：字节；KB/MB 按 1000 进位，KiB/MiB 按 1024，与 macOS 一致）
        add(.data, 1, "b", "byte", "bytes", "字节")
        add(.data, 1000, "kb")
        add(.data, 1_000_000, "mb")
        add(.data, 1_000_000_000, "gb")
        add(.data, 1_000_000_000_000, "tb")
        add(.data, 1024, "kib")
        add(.data, 1_048_576, "mib")
        add(.data, 1_073_741_824, "gib")
        add(.data, 1_099_511_627_776, "tib")
        return table
    }()

    /// 是否是已知的普通单位（不含温度、货币）
    static func isKnownUnit(_ name: String) -> Bool {
        table[normalize(name)] != nil
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// 普通单位换算；类别不同或单位未知返回 `nil`
    static func convert(value: Double, from: String, to: String) -> Double? {
        guard let source = table[normalize(from)], let target = table[normalize(to)],
            source.category == target.category
        else { return nil }
        return value * source.factor / target.factor
    }

    // MARK: - 温度

    private enum TemperatureUnit {
        case celsius, fahrenheit, kelvin

        init?(_ name: String) {
            switch name.trimmingCharacters(in: .whitespaces).lowercased() {
            case "c", "°c", "℃", "摄氏", "摄氏度", "celsius": self = .celsius
            case "f", "°f", "℉", "华氏", "华氏度", "fahrenheit": self = .fahrenheit
            case "k", "开", "开尔文", "kelvin": self = .kelvin
            default: return nil
            }
        }

        var symbol: String {
            switch self {
            case .celsius: "°C"
            case .fahrenheit: "°F"
            case .kelvin: "K"
            }
        }

        func toCelsius(_ value: Double) -> Double {
            switch self {
            case .celsius: value
            case .fahrenheit: (value - 32) * 5 / 9
            case .kelvin: value - 273.15
            }
        }

        func fromCelsius(_ celsius: Double) -> Double {
            switch self {
            case .celsius: celsius
            case .fahrenheit: celsius * 9 / 5 + 32
            case .kelvin: celsius + 273.15
            }
        }
    }

    /// 温度换算；任一边不是温度单位返回 `nil`。返回数值与目标单位符号（°C / °F / K）
    static func convertTemperature(value: Double, from: String, to: String) -> (value: Double, symbol: String)? {
        guard let source = TemperatureUnit(from), let target = TemperatureUnit(to) else { return nil }
        return (target.fromCelsius(source.toCelsius(value)), target.symbol)
    }

    // MARK: - 解析

    /// 一次换算请求：`100 km to mi`
    struct Request: Equatable, Sendable {
        let value: Double
        let fromUnit: String
        let toUnit: String
    }

    /// 英文分隔词：必须是独立单词，否则 `photoshop` 里的 `to`、`settings` 里的 `in` 都会被当成换算
    private static let wordSeparators = ["to", "in"]
    /// 符号与中文分隔：不要求空格（`100km转mi`），较长的在前，先匹配
    private static let symbolSeparators = ["转换为", "转换成", "换算成", "转成", "换成", "转为", "->", "=>", "→", "转", "换"]

    /// 找出所有可能的「数值+源单位 | 目标单位」切法
    ///
    /// 单位名本身可能含分隔词（`in` 是英寸，`min` 里有 `in`），所以不能只取第一处，
    /// 要把每个候选都交给调用方试一遍，直到某个切法两边都是已知单位。
    static func requests(in expression: String) -> [Request] {
        let text = expression.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let first = text.first, first.isNumber || first == "." || first == "-" else { return [] }
        let chars = Array(text)
        var results: [Request] = []

        func attempt(left: String, right: String) {
            let right = right.trimmingCharacters(in: .whitespaces)
            guard !right.isEmpty else { return }
            let scanner = Scanner(string: left.replacingOccurrences(of: ",", with: ""))
            scanner.charactersToBeSkipped = .whitespaces
            guard let value = scanner.scanDouble() else { return }
            let unit = String(scanner.string[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)
            guard !unit.isEmpty else { return }
            results.append(Request(value: value, fromUnit: unit, toUnit: right))
        }

        var index = 0
        while index < chars.count {
            let rest = String(chars[index...])
            if let symbol = symbolSeparators.first(where: { rest.hasPrefix($0) }) {
                attempt(left: String(chars[..<index]), right: String(rest.dropFirst(symbol.count)))
            } else if let word = wordSeparators.first(where: { rest.hasPrefix($0) }) {
                let before = index > 0 ? chars[index - 1] : " "
                let afterIndex = index + word.count
                let after = afterIndex < chars.count ? chars[afterIndex] : " "
                if (before.isWhitespace || before.isNumber || before == ")") && after.isWhitespace {
                    attempt(left: String(chars[..<index]), right: String(rest.dropFirst(word.count)))
                }
            }
            index += 1
        }
        return results
    }

    /// 输入是否长得像换算（给搜索闸门用，比真正求值便宜得多）
    static func looksLikeConversion(_ expression: String) -> Bool {
        !requests(in: expression).isEmpty
    }
}
