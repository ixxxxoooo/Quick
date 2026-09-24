// CalcEngine.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 计算引擎
///
/// 解析并计算数学表达式。使用 NSExpression 作为后端，
/// 支持四则运算、括号、幂运算等。
///
/// **无状态且 `Sendable`，所以是 `nonisolated`。** 搜索闸门（`accepts`）与求值
/// 都在面板按键的热路径上，留在主 actor 上会让计算和渲染互相排队。引擎不持有
/// 任何可变状态，令牌化与解析各自新建局部对象，因此脱离主 actor 是安全的。
nonisolated final class CalcEngine: Sendable {

    /// 计算结果
    struct CalcResult: Sendable {
        let value: Double
        let formatted: String
    }

    /// 计算表达式
    /// - Parameters:
    ///   - expression: 用户输入的表达式字符串
    ///   - options: 显示选项（小数位数、千分位）。由调用方从设置里读好再传进来 ——
    ///     引擎不认识 `UserDefaults`，设置页改了值调用方下次传新的就行
    /// - Returns: 计算结果（无法解析则返回 nil）
    func evaluate(_ expression: String, options: CalcDisplayOptions = .default) -> CalcResult? {
        let cleaned = cleanExpression(expression)
        guard !cleaned.isEmpty else { return nil }
        guard looksLikeExpression(cleaned) else { return nil }

        // 尝试单位换算
        if let unitResult = tryUnitConversion(cleaned, options: options) {
            return unitResult
        }

        // 数学表达式计算
        return tryMathExpression(cleaned, options: options)
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
    ///
    /// 给搜索闸门用：不像表达式就不要进求值，主面板每次按键都会问一次。
    func looksLikeExpression(_ expr: String) -> Bool {
        let unitKeywords = ["to", "in", "转", "换"]
        if unitKeywords.contains(where: { expr.lowercased().contains($0) }) {
            return true
        }

        let mathOperators = "+-*/^%×÷"
        if expr.contains(where: { mathOperators.contains($0) }) {
            return true
        }

        let mathFunctions = [
            "sqrt", "cbrt", "sin", "cos", "tan", "asin", "acos", "atan",
            "log", "log10", "log2", "ln", "abs", "round", "floor", "ceil", "exp"
        ]
        let lower = expr.lowercased()
        if mathFunctions.contains(where: { lower.hasPrefix($0 + "(") || lower.hasPrefix($0 + "（") }) {
            return true
        }

        return false
    }

    // MARK: - 数学表达式

    /// 使用纯 Swift 解析并计算数学表达式（杜绝 NSExpression 引发的未捕获异常崩溃）
    private func tryMathExpression(_ expr: String, options: CalcDisplayOptions) -> CalcResult? {
        guard let tokens = MathTokenizer(input: expr).tokenize() else { return nil }
        var parser = MathParser(tokens: tokens)
        guard let value = parser.parse() else { return nil }
        return CalcResult(value: value, formatted: CalcFormatting.string(from: value, options: options))
    }

    // MARK: - 单位换算

    /// 尝试解析单位换算表达式（如 "100 km to mi"）
    private func tryUnitConversion(_ expr: String, options: CalcDisplayOptions) -> CalcResult? {
        // 简单的单位换算模式匹配
        let patterns = ["to", "in", "转", "换"]
        for separator in patterns {
            let parts = expr.lowercased().components(separatedBy: " \(separator) ")
            guard parts.count == 2 else { continue }

            let source = parts[0].trimmingCharacters(in: .whitespaces)
            let targetUnit = parts[1].trimmingCharacters(in: .whitespaces)

            if let result = convertUnit(source: source, targetUnit: targetUnit, options: options) {
                return result
            }
        }
        return nil
    }

    /// 执行单位转换
    private func convertUnit(
        source: String,
        targetUnit: String,
        options: CalcDisplayOptions
    ) -> CalcResult? {
        // 解析数值和单位
        let scanner = Scanner(string: source)
        guard let value = scanner.scanDouble() else { return nil }
        let sourceUnit = String(source[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)

        // 温度换算
        if let result = convertTemperature(value: value, from: sourceUnit, to: targetUnit, options: options) {
            return result
        }

        // 使用 Measurement API 进行通用单位换算
        if let result = convertMeasurement(
            value: value, from: sourceUnit, to: targetUnit, options: options)
        {
            return result
        }

        return nil
    }

    /// 温度转换
    private func convertTemperature(
        value: Double,
        from: String,
        to: String,
        options: CalcDisplayOptions
    ) -> CalcResult? {
        let celsiusNames = ["c", "°c", "摄氏", "celsius"]
        let fahrenheitNames = ["f", "°f", "华氏", "fahrenheit"]

        let fromCelsius = celsiusNames.contains(from.lowercased())
        let fromFahrenheit = fahrenheitNames.contains(from.lowercased())
        let toCelsius = celsiusNames.contains(to.lowercased())
        let toFahrenheit = fahrenheitNames.contains(to.lowercased())

        if fromCelsius && toFahrenheit {
            let result = value * 9 / 5 + 32
            return CalcResult(
                value: result, formatted: "\(CalcFormatting.string(from: result, options: options))°F")
        }
        if fromFahrenheit && toCelsius {
            let result = (value - 32) * 5 / 9
            return CalcResult(
                value: result, formatted: "\(CalcFormatting.string(from: result, options: options))°C")
        }

        return nil
    }

    /// 使用 Measurement API 进行换算
    private func convertMeasurement(
        value: Double,
        from: String,
        to: String,
        options: CalcDisplayOptions
    ) -> CalcResult? {
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
                formatted: "\(CalcFormatting.string(from: converted.value, options: options)) \(to)"
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
                formatted: "\(CalcFormatting.string(from: converted.value, options: options)) \(to)"
            )
        }

        return nil
    }
}

// MARK: - 纯 Swift 数学解析引擎 (零崩溃保证)

enum MathToken: Equatable, Sendable {
    case number(Double)
    case identifier(String)
    case plus
    case minus
    case multiply
    case divide
    case modulo
    case power
    case leftParen
    case rightParen
}

struct MathTokenizer: Sendable {
    let input: String

    func tokenize() -> [MathToken]? {
        var tokens: [MathToken] = []
        var index = input.startIndex

        while index < input.endIndex {
            let char = input[index]

            if char.isWhitespace {
                index = input.index(after: index)
                continue
            }

            switch char {
            case "+":
                tokens.append(.plus)
                index = input.index(after: index)
            case "-":
                tokens.append(.minus)
                index = input.index(after: index)
            case "*", "×":
                let next = input.index(after: index)
                if next < input.endIndex && input[next] == "*" {
                    tokens.append(.power)
                    index = input.index(after: next)
                } else {
                    tokens.append(.multiply)
                    index = next
                }
            case "/", "÷":
                tokens.append(.divide)
                index = input.index(after: index)
            case "%":
                tokens.append(.modulo)
                index = input.index(after: index)
            case "^":
                tokens.append(.power)
                index = input.index(after: index)
            case "(", "（":
                tokens.append(.leftParen)
                index = input.index(after: index)
            case ")", "）":
                tokens.append(.rightParen)
                index = input.index(after: index)
            case "0"..."9", ".":
                let start = index
                var hasDot = (char == ".")
                index = input.index(after: index)
                while index < input.endIndex {
                    let c = input[index]
                    if c.isNumber {
                        index = input.index(after: index)
                    } else if c == "." && !hasDot {
                        hasDot = true
                        index = input.index(after: index)
                    } else {
                        break
                    }
                }
                let numStr = String(input[start..<index])
                guard let val = Double(numStr) else { return nil }
                tokens.append(.number(val))
            case "a"..."z", "A"..."Z", "π":
                let start = index
                index = input.index(after: index)
                while index < input.endIndex
                    && (input[index].isLetter || input[index].isNumber || input[index] == "_")
                {
                    index = input.index(after: index)
                }
                let name = String(input[start..<index]).lowercased()
                tokens.append(.identifier(name))
            default:
                return nil
            }
        }
        return tokens
    }
}

/// 数学表达式解析器
///
/// **值类型。** 它持有游标 `pos`，而同一个实例被两个线程共享就会真的竞争 ——
/// 之前用 `@unchecked Sendable` 把这件事压了下去，本项目只允许 Carbon 回调跳板
/// 用那个（见 docs/standards.md）。改成 `struct` 后每个调用点各自持有一份游标，
/// 编译器能自己证明安全，不需要任何断言。
struct MathParser: Sendable {
    private let tokens: [MathToken]
    private var pos: Int = 0

    init(tokens: [MathToken]) {
        self.tokens = tokens
    }

    private var current: MathToken? {
        pos < tokens.count ? tokens[pos] : nil
    }

    mutating func advance() -> MathToken? {
        guard pos < tokens.count else { return nil }
        let tok = tokens[pos]
        pos += 1
        return tok
    }

    mutating func parse() -> Double? {
        guard !tokens.isEmpty else { return nil }
        guard let result = parseExpression() else { return nil }
        guard pos == tokens.count, result.isFinite else { return nil }
        return result
    }

    // expression = term (('+' | '-') term)*
    private mutating func parseExpression() -> Double? {
        guard var value = parseTerm() else { return nil }
        while let tok = current {
            if tok == .plus {
                _ = advance()
                guard let right = parseTerm() else { return nil }
                value += right
            } else if tok == .minus {
                _ = advance()
                guard let right = parseTerm() else { return nil }
                value -= right
            } else {
                break
            }
        }
        return value
    }

    // term = power (('*' | '/' | '%') power)*
    private mutating func parseTerm() -> Double? {
        guard var value = parsePower() else { return nil }
        while let tok = current {
            if tok == .multiply {
                _ = advance()
                guard let right = parsePower() else { return nil }
                value *= right
            } else if tok == .divide {
                _ = advance()
                guard let right = parsePower(), right != 0 else { return nil }
                value /= right
            } else if tok == .modulo {
                _ = advance()
                guard let right = parsePower(), right != 0 else { return nil }
                value = value.truncatingRemainder(dividingBy: right)
            } else {
                break
            }
        }
        return value
    }

    // power = unary ('^' power)?
    private mutating func parsePower() -> Double? {
        guard let base = parseUnary() else { return nil }
        if current == .power {
            _ = advance()
            guard let exponent = parsePower() else { return nil }
            let res = pow(base, exponent)
            guard res.isFinite else { return nil }
            return res
        }
        return base
    }

    // unary = ('+' | '-') unary | primary
    private mutating func parseUnary() -> Double? {
        if current == .plus {
            _ = advance()
            return parseUnary()
        } else if current == .minus {
            _ = advance()
            guard let val = parseUnary() else { return nil }
            return -val
        }
        return parsePrimary()
    }

    // primary = number | identifier | '(' expression ')'
    private mutating func parsePrimary() -> Double? {
        guard let tok = advance() else { return nil }
        switch tok {
        case .number(let val):
            return val
        case .identifier(let name):
            if name == "pi" || name == "π" {
                return Double.pi
            }
            if name == "e" {
                return M_E
            }
            if current == .leftParen {
                _ = advance()
                guard let arg = parseExpression() else { return nil }
                guard advance() == .rightParen else { return nil }
                return evaluateFunction(name, arg: arg)
            }
            return nil
        case .leftParen:
            guard let expr = parseExpression() else { return nil }
            guard advance() == .rightParen else { return nil }
            return expr
        default:
            return nil
        }
    }

    private mutating func evaluateFunction(_ name: String, arg: Double) -> Double? {
        switch name {
        case "sqrt":
            guard arg >= 0 else { return nil }
            return sqrt(arg)
        case "cbrt":
            return cbrt(arg)
        case "abs":
            return abs(arg)
        case "sin":
            return sin(arg)
        case "cos":
            return cos(arg)
        case "tan":
            return tan(arg)
        case "asin":
            guard (-1.0...1.0).contains(arg) else { return nil }
            return asin(arg)
        case "acos":
            guard (-1.0...1.0).contains(arg) else { return nil }
            return acos(arg)
        case "atan":
            return atan(arg)
        case "log", "log10":
            guard arg > 0 else { return nil }
            return log10(arg)
        case "ln":
            guard arg > 0 else { return nil }
            return log(arg)
        case "log2":
            guard arg > 0 else { return nil }
            return log2(arg)
        case "exp":
            return exp(arg)
        case "floor":
            return floor(arg)
        case "ceil":
            return ceil(arg)
        case "round":
            return round(arg)
        default:
            return nil
        }
    }
}
