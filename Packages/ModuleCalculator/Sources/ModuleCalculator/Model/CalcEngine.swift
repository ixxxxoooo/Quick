// CalcEngine.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 计算引擎
///
/// 解析并计算数学表达式。使用 NSExpression 作为后端，
/// 支持四则运算、括号、幂运算等。
@MainActor
final class CalcEngine {

    /// 计算结果
    struct CalcResult: Sendable {
        let value: Double
        let formatted: String
    }

    /// 计算表达式
    /// - Parameter expression: 用户输入的表达式字符串
    /// - Returns: 计算结果（无法解析则返回 nil）
    func evaluate(_ expression: String) -> CalcResult? {
        let cleaned = cleanExpression(expression)
        guard !cleaned.isEmpty else { return nil }
        guard looksLikeExpression(cleaned) else { return nil }

        // 尝试单位换算
        if let unitResult = tryUnitConversion(cleaned) {
            return unitResult
        }

        // 数学表达式计算
        return tryMathExpression(cleaned)
    }

    // MARK: - 表达式清理

    /// 清理表达式字符串（替换中文符号等）
    private func cleanExpression(_ expr: String) -> String {
        var result = expr.trimmingCharacters(in: .whitespaces)
        result = result.replacingOccurrences(of: "×", with: "*")
        result = result.replacingOccurrences(of: "÷", with: "/")
        result = result.replacingOccurrences(of: "（", with: "(")
        result = result.replacingOccurrences(of: "）", with: ")")
        return result
    }

    /// 判断输入是否像数学表达式
    private func looksLikeExpression(_ expr: String) -> Bool {
        let mathChars = CharacterSet(charactersIn: "0123456789+-*/().%^ ")
        let unitKeywords = ["to", "in", "转", "换"]
        if unitKeywords.contains(where: { expr.lowercased().contains($0) }) {
            return true
        }
        return expr.unicodeScalars.allSatisfy { mathChars.contains($0) }
            && expr.contains(where: { "+-*/^%".contains($0) })
    }

    // MARK: - 数学表达式

    /// 使用 NSExpression 计算数学表达式
    private func tryMathExpression(_ expr: String) -> CalcResult? {
        // 替换 ^ 为 ** (NSExpression 的幂运算)
        let nsExpr = expr.replacingOccurrences(of: "^", with: "**")

        do {
            let expression = try NSExpression(format: nsExpr)
            guard let value = expression.expressionValue(with: nil, context: nil) as? NSNumber else {
                return nil
            }
            let doubleValue = value.doubleValue
            return CalcResult(value: doubleValue, formatted: formatNumber(doubleValue))
        } catch {
            return nil
        }
    }

    // MARK: - 单位换算

    /// 尝试解析单位换算表达式（如 "100 km to mi"）
    private func tryUnitConversion(_ expr: String) -> CalcResult? {
        // 简单的单位换算模式匹配
        let patterns = ["to", "in", "转", "换"]
        for separator in patterns {
            let parts = expr.lowercased().components(separatedBy: " \(separator) ")
            guard parts.count == 2 else { continue }

            let source = parts[0].trimmingCharacters(in: .whitespaces)
            let targetUnit = parts[1].trimmingCharacters(in: .whitespaces)

            if let result = convertUnit(source: source, targetUnit: targetUnit) {
                return result
            }
        }
        return nil
    }

    /// 执行单位转换
    private func convertUnit(source: String, targetUnit: String) -> CalcResult? {
        // 解析数值和单位
        let scanner = Scanner(string: source)
        guard let value = scanner.scanDouble() else { return nil }
        let sourceUnit = String(source[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)

        // 温度换算
        if let result = convertTemperature(value: value, from: sourceUnit, to: targetUnit) {
            return result
        }

        // 使用 Measurement API 进行通用单位换算
        if let result = convertMeasurement(value: value, from: sourceUnit, to: targetUnit) {
            return result
        }

        return nil
    }

    /// 温度转换
    private func convertTemperature(value: Double, from: String, to: String) -> CalcResult? {
        let celsiusNames = ["c", "°c", "摄氏", "celsius"]
        let fahrenheitNames = ["f", "°f", "华氏", "fahrenheit"]

        let fromCelsius = celsiusNames.contains(from.lowercased())
        let fromFahrenheit = fahrenheitNames.contains(from.lowercased())
        let toCelsius = celsiusNames.contains(to.lowercased())
        let toFahrenheit = fahrenheitNames.contains(to.lowercased())

        if fromCelsius && toFahrenheit {
            let result = value * 9 / 5 + 32
            return CalcResult(value: result, formatted: "\(formatNumber(result))°F")
        }
        if fromFahrenheit && toCelsius {
            let result = (value - 32) * 5 / 9
            return CalcResult(value: result, formatted: "\(formatNumber(result))°C")
        }

        return nil
    }

    /// 使用 Measurement API 进行换算
    private func convertMeasurement(value: Double, from: String, to: String) -> CalcResult? {
        // 长度单位映射
        let lengthUnits: [String: UnitLength] = [
            "km": .kilometers, "m": .meters, "cm": .centimeters, "mm": .millimeters,
            "mi": .miles, "yd": .yards, "ft": .feet, "in": .inches,
            "千米": .kilometers, "米": .meters, "厘米": .centimeters, "英里": .miles
        ]

        // 重量单位映射
        let massUnits: [String: UnitMass] = [
            "kg": .kilograms, "g": .grams, "mg": .milligrams,
            "lb": .pounds, "oz": .ounces,
            "千克": .kilograms, "克": .grams, "磅": .pounds
        ]

        // 尝试长度换算
        if let fromUnit = lengthUnits[from.lowercased()],
            let toUnit = lengthUnits[to.lowercased()]
        {
            let measurement = Measurement(value: value, unit: fromUnit)
            let converted = measurement.converted(to: toUnit)
            return CalcResult(
                value: converted.value,
                formatted: "\(formatNumber(converted.value)) \(to)"
            )
        }

        // 尝试重量换算
        if let fromUnit = massUnits[from.lowercased()],
            let toUnit = massUnits[to.lowercased()]
        {
            let measurement = Measurement(value: value, unit: fromUnit)
            let converted = measurement.converted(to: toUnit)
            return CalcResult(
                value: converted.value,
                formatted: "\(formatNumber(converted.value)) \(to)"
            )
        }

        return nil
    }

    // MARK: - 格式化

    /// 格式化数字（去除多余小数位）
    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
