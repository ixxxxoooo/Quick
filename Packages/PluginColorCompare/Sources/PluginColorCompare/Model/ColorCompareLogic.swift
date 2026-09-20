// ColorCompareLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 解析的颜色条目
///
/// 只持有数值和字符串，不持有 `Color` —— `Model/` 目录禁止引 SwiftUI（仓库红线），
/// 因此视图层需要的 `Color` 由 View 文件里的扩展补上。
struct ParsedColor: Identifiable, Sendable {
    let id = UUID()
    let hex: String
    let r: Double
    let g: Double
    let b: Double

    var rgbString: String { "rgb(\(Int(r)), \(Int(g)), \(Int(b)))" }

    /// 相对亮度（WCAG）
    var luminance: Double {
        func sRGB(_ v: Double) -> Double {
            let s = v / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * sRGB(r) + 0.7152 * sRGB(g) + 0.0722 * sRGB(b)
    }
}

/// 颜色识别与转换的纯逻辑
///
/// 从视图里抽出来是为了能脱离界面测试：输入文本 → 颜色条目、亮度排序、复制文本，
/// 三件都不需要 `@State`，也都不碰 SwiftUI。
enum ColorCompareLogic {

    /// 从任意文本里识别颜色
    ///
    /// 两趟扫描（先全部 `#HEX`，再全部 `rgb()`）而不是一趟混扫，所以结果的顺序
    /// 是「先 hex 后 rgb」，跟颜色在文本里出现的先后无关 —— 保持这个行为，
    /// 卡片网格和亮度条的排列都依赖它。
    ///
    /// - Parameter text: 用户输入的文本
    /// - Returns: 识别到的颜色条目，顺序同上述两趟扫描
    static func parse(_ text: String) -> [ParsedColor] {
        var parsed: [ParsedColor] = []

        // 匹配 #HEX
        let hexPattern = "#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})"
        if let regex = try? NSRegularExpression(pattern: hexPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    let hex = String(text[range])
                    if let color = parseHex(hex) { parsed.append(color) }
                }
            }
        }

        // 匹配 rgb(r, g, b)
        let rgbPattern = "rgb\\s*\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\)"
        if let regex = try? NSRegularExpression(pattern: rgbPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let rRange = Range(match.range(at: 1), in: text),
                    let gRange = Range(match.range(at: 2), in: text),
                    let bRange = Range(match.range(at: 3), in: text),
                    let r = Double(text[rRange]),
                    let g = Double(text[gRange]),
                    let b = Double(text[bRange])
                {
                    // 分量必须夹到 0...255：`rgb(300, 0, 0)` 是合法输入，
                    // 但让它原样流下去会拼出 `#12C0000` 这种 7 位色值，
                    // 色卡和亮度也都不对了。CSS 同样是夹取而不是报错。
                    let red = clamp(r)
                    let green = clamp(g)
                    let blue = clamp(b)
                    let hex = String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue))
                    parsed.append(ParsedColor(hex: hex, r: red, g: green, b: blue))
                }
            }
        }

        return parsed
    }

    /// 把 RGB 分量夹到 0...255 并取整
    private static func clamp(_ value: Double) -> Double {
        min(max(value.rounded(), 0), 255)
    }

    /// 解析单个 `#HEX`
    ///
    /// - Parameter hex: 形如 `#A1B2C3` 或 `#ABC` 的字符串（`#` 可有可无、可多个）
    /// - Returns: 颜色条目；位数不对或含非十六进制字符时返回 nil
    static func parseHex(_ hex: String) -> ParsedColor? {
        var clean = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        if clean.count == 3 {
            clean = clean.map { "\($0)\($0)" }.joined()
        }
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF)
        let g = Double((value >> 8) & 0xFF)
        let b = Double(value & 0xFF)
        return ParsedColor(hex: "#\(clean.uppercased())", r: r, g: g, b: b)
    }

    /// 按相对亮度从亮到暗排序
    ///
    /// - Parameter colors: 待排序的颜色
    /// - Returns: 新数组，亮度条按此顺序自上而下排列
    static func sortedByLuminance(_ colors: [ParsedColor]) -> [ParsedColor] {
        colors.sorted(by: { $0.luminance > $1.luminance })
    }

    /// 「全部复制」输出的文本
    ///
    /// - Parameter colors: 要导出的颜色
    /// - Returns: 每行一个颜色，`HEX | rgb(...)` 用竖线分隔
    static func copyText(_ colors: [ParsedColor]) -> String {
        colors.map { "\($0.hex) | \($0.rgbString)" }.joined(separator: "\n")
    }
}
