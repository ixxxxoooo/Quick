// SmartPreviewDetector.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 智能预览检测器（对齐 Fasty `smart_preview::detect`）
///
/// 纯函数、无 IO 副作用（文件路径存在性除外，由注入的 `fileExists` 提供，
/// 测试可注入假文件系统）。返回所有命中的预览类型。
public enum SmartPreviewDetector {

    /// 检测文本类型
    ///
    /// - Parameters:
    ///   - text: 剪贴板或选中文本
    ///   - fileExists: 路径是否存在（默认真实文件系统）
    ///   - isDirectory: 路径是否为目录
    ///   - now: 当前时间（时间戳相对描述用，测试可注入）
    /// - Returns: 匹配到的预览列表；空输入返回空数组
    public static func detect(
        _ text: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isDirectory: (String) -> Bool = { path in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return isDir.boolValue
        },
        now: Date = Date()
    ) -> [SmartPreview] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var previews: [SmartPreview] = []

        if let preview = detectFilePath(trimmed, fileExists: fileExists, isDirectory: isDirectory) {
            previews.append(preview)
        }
        if let preview = detectTimestamp(trimmed, now: now) {
            previews.append(preview)
        }
        if let preview = detectURL(trimmed) {
            previews.append(preview)
        }
        if let preview = detectURLEncoded(trimmed) {
            previews.append(preview)
        }
        if let preview = detectBase64(trimmed) {
            previews.append(preview)
        }
        if let preview = detectColor(trimmed) {
            previews.append(preview)
        }
        if let preview = detectIP(trimmed) {
            previews.append(preview)
        }
        if let preview = detectJSON(trimmed) {
            previews.append(preview)
        }
        if let preview = detectSQL(trimmed) {
            previews.append(preview)
        }
        if let preview = detectMath(trimmed) {
            previews.append(preview)
        }
        if let preview = detectPhone(trimmed) {
            previews.append(preview)
        }
        if let preview = detectEmail(trimmed) {
            previews.append(preview)
        }
        if let preview = detectTranslationCandidate(trimmed) {
            previews.append(preview)
        }

        if previews.isEmpty {
            let summary = trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed
            previews.append(.plainText(summary: summary, charCount: trimmed.count))
        }

        return previews
    }

    // MARK: - 各类型

    private static func detectFilePath(
        _ text: String,
        fileExists: (String) -> Bool,
        isDirectory: (String) -> Bool
    ) -> SmartPreview? {
        guard text.hasPrefix("/") || text.hasPrefix("~") else { return nil }
        guard !text.contains("://") else { return nil }
        guard !text.contains("\n"), text.count < 512 else { return nil }

        let expanded: String
        if text.hasPrefix("~") {
            let home = NSHomeDirectory()
            expanded = text == "~" ? home : home + text.dropFirst()
        } else {
            expanded = text
        }

        let exists = fileExists(expanded)
        return .filePath(path: expanded, exists: exists, isDirectory: exists && isDirectory(expanded))
    }

    private static func detectTimestamp(_ text: String, now: Date) -> SmartPreview? {
        guard text.allSatisfy(\.isNumber), text.count == 10 || text.count == 13 else { return nil }
        guard let value = Double(text) else { return nil }

        let seconds = text.count == 13 ? value / 1000 : value
        // 合理范围：2001 ~ 2100
        guard seconds > 1_000_000_000, seconds < 4_102_444_800 else { return nil }

        let date = Date(timeIntervalSince1970: seconds)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = .current
        let formatted = formatter.string(from: date)

        let relative = relativeDescription(from: date, to: now)
        return .timestamp(original: text, formatted: formatted, relative: relative)
    }

    private static func relativeDescription(from date: Date, to now: Date) -> String {
        let delta = now.timeIntervalSince(date)
        let absDelta = abs(delta)
        let suffix = delta >= 0 ? "前" : "后"
        if absDelta < 60 { return "刚刚" }
        if absDelta < 3600 { return "\(Int(absDelta / 60)) 分钟\(suffix)" }
        if absDelta < 86400 { return "\(Int(absDelta / 3600)) 小时\(suffix)" }
        return "\(Int(absDelta / 86400)) 天\(suffix)"
    }

    private static func detectURL(_ text: String) -> SmartPreview? {
        if detectIP(text) != nil { return nil }
        if text.contains("@") { return nil }

        let candidate: String
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            candidate = text
        } else if text.contains(".") && !text.contains(" ") && text.count > 3 {
            candidate = "https://\(text)"
        } else {
            return nil
        }

        guard let url = URL(string: candidate), let host = url.host, !host.isEmpty else { return nil }
        if text.hasPrefix("/") { return nil }
        guard host.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return nil
        }
        return .url(url: candidate, domain: host)
    }

    private static func detectURLEncoded(_ text: String) -> SmartPreview? {
        guard text.contains("%"), text.range(of: "%[0-9A-Fa-f]{2}", options: .regularExpression) != nil
        else { return nil }
        guard let decoded = text.removingPercentEncoding, decoded != text, !decoded.isEmpty else {
            return nil
        }
        return .urlEncoded(decoded: decoded)
    }

    private static func detectBase64(_ text: String) -> SmartPreview? {
        guard text.count >= 16, !text.contains(" "), !text.contains("\n") else { return nil }
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard let data = Data(base64Encoded: text), !data.isEmpty else { return nil }
        guard let decoded = String(data: data, encoding: .utf8), !decoded.isEmpty else { return nil }
        guard
            decoded.unicodeScalars.allSatisfy({ $0.isASCII && ($0.value >= 32 || $0 == "\n" || $0 == "\t") })
        else { return nil }
        return .base64(decoded: decoded)
    }

    private static func detectColor(_ text: String) -> SmartPreview? {
        let hex: String
        if text.hasPrefix("#") {
            hex = String(text.dropFirst())
        } else {
            hex = text
        }
        guard hex.count == 3 || hex.count == 6 || hex.count == 8 else { return nil }
        guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }

        let full: String
        if hex.count == 3 {
            full = hex.map { "\($0)\($0)" }.joined()
        } else {
            full = String(hex.prefix(6))
        }
        guard let r = Int(full.prefix(2), radix: 16),
            let g = Int(full.dropFirst(2).prefix(2), radix: 16),
            let b = Int(full.dropFirst(4).prefix(2), radix: 16)
        else { return nil }

        return .color(hex: "#\(full.uppercased())", rgb: "rgb(\(r), \(g), \(b))")
    }

    private static func detectIP(_ text: String) -> SmartPreview? {
        let parts = text.split(separator: ".")
        guard parts.count == 4 else { return nil }
        for part in parts {
            guard let n = Int(part), (0...255).contains(n) else { return nil }
        }
        return .ip(address: text)
    }

    private static func detectJSON(_ text: String) -> SmartPreview? {
        guard let first = text.first, first == "{" || first == "[" else { return nil }
        guard let data = text.data(using: .utf8),
            (try? JSONSerialization.jsonObject(with: data)) != nil
        else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let summary = first == "{" ? "对象" : "数组"
        return .json(summary: summary, lineCount: lines)
    }

    /// SQL 语句的起始关键字
    private static let sqlStarters: Set<String> = [
        "SELECT", "WITH", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP",
        "MERGE", "REPLACE", "TRUNCATE", "GRANT", "REVOKE", "EXPLAIN", "SHOW", "DESCRIBE", "USE", "CALL"
    ]

    /// `SELECT` / `WITH` 特有的强信号：没有它就很可能只是以 Select 开头的英文句子
    private static let selectStrongMarkers = [
        " WHERE ", " GROUP ", " ORDER ", " JOIN ", " LIMIT ", " HAVING ", " UNION ", " OFFSET ", " *"
    ]

    /// DML / DDL 关键字后跟的结构标记
    private static let statementStructureMarkers = [
        " FROM ", " VALUES ", " SET ", " INTO ", " TABLE ", " ON ", " ("
    ]

    /// 识别 SQL 语句
    ///
    /// 只看「起始关键字 + 结构标记」两个信号，不做真正的语法分析 —— 目标是认出
    /// 用户复制/选中的一段 SQL 并给出「用 SQL 格式化打开」的入口，不是校验语法。
    /// 因为「Select … from …」也可能是英文句子，`SELECT` / `WITH` 需要额外强信号
    /// （WHERE / JOIN / `*` …）才判为 SQL。
    private static func detectSQL(_ text: String) -> SmartPreview? {
        guard text.count >= 12, text.count <= 20_000 else { return nil }
        let upper = text.uppercased()
        let leading = upper.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord =
            leading.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "(" })
            .first.map(String.init) ?? ""
        guard sqlStarters.contains(firstWord) else { return nil }

        let markers =
            (firstWord == "SELECT" || firstWord == "WITH")
            ? selectStrongMarkers : statementStructureMarkers
        guard markers.contains(where: { upper.contains($0) }) else { return nil }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return .sql(statement: firstWord, lineCount: lines)
    }

    private static func detectMath(_ text: String) -> SmartPreview? {
        guard text.count >= 3, text.count <= 120 else { return nil }
        guard text.first?.isNumber == true || text.first == "(" else { return nil }

        let allowed = CharacterSet(charactersIn: "0123456789.+-*/() ")
        guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        let hasOp = text.contains(where: { "+-*/".contains($0) })
        guard hasOp else { return nil }

        guard let value = evaluateArithmetic(text) else { return nil }
        let result: String
        if value == floor(value), abs(value) < 1e15 {
            result = String(format: "%.0f", value)
        } else {
            result = String(format: "%g", value)
        }
        return .math(expr: text, result: result)
    }

    /// 极简四则求值（中缀，支持括号），失败返回 nil
    private static func evaluateArithmetic(_ input: String) -> Double? {
        var s = input.replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }

        func parseExpr() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let c = s.first, c == "+" || c == "-" {
                s.removeFirst()
                guard let rhs = parseTerm() else { return nil }
                value = c == "+" ? value + rhs : value - rhs
            }
            return value
        }

        func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while let c = s.first, c == "*" || c == "/" {
                s.removeFirst()
                guard let rhs = parseFactor() else { return nil }
                if c == "/" {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
            return value
        }

        func parseFactor() -> Double? {
            if s.first == "(" {
                s.removeFirst()
                guard let value = parseExpr() else { return nil }
                guard s.first == ")" else { return nil }
                s.removeFirst()
                return value
            }
            if s.first == "-" {
                s.removeFirst()
                guard let value = parseFactor() else { return nil }
                return -value
            }
            if s.first == "+" {
                s.removeFirst()
                return parseFactor()
            }
            var num = ""
            while let c = s.first, c.isNumber || c == "." {
                num.append(c)
                s.removeFirst()
            }
            return Double(num)
        }

        guard let value = parseExpr(), s.isEmpty else { return nil }
        return value
    }

    private static func detectPhone(_ text: String) -> SmartPreview? {
        let digits = text.filter(\.isNumber)
        if digits.count == 11, digits.hasPrefix("1") {
            let formatted =
                "\(digits.prefix(3)) \(digits.dropFirst(3).prefix(4)) \(digits.dropFirst(7))"
            return .phone(formatted: formatted)
        }
        if digits.count == 13, digits.hasPrefix("86") {
            let local = String(digits.dropFirst(2))
            let formatted =
                "+86 \(local.prefix(3)) \(local.dropFirst(3).prefix(4)) \(local.dropFirst(7))"
            return .phone(formatted: formatted)
        }
        return nil
    }

    private static func detectEmail(_ text: String) -> SmartPreview? {
        guard text.contains("@"), !text.contains(" ") else { return nil }
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        guard text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return nil
        }
        return .email(email: text)
    }

    private static func detectTranslationCandidate(_ text: String) -> SmartPreview? {
        guard text.count >= 2, text.count <= 500 else { return nil }
        let hasHan = text.contains { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }
        let letters = text.filter { $0.isLetter }
        guard letters.count >= 2 else { return nil }

        if hasHan {
            return .translation(source: String(text.prefix(80)), detectedLang: "zh")
        }
        let latinRatio = Double(letters.count) / Double(max(text.count, 1))
        guard latinRatio > 0.6 else { return nil }
        return .translation(source: String(text.prefix(80)), detectedLang: "en")
    }
}
