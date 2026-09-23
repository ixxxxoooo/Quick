// Base64CodecLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// Base64 编解码的纯逻辑
///
/// 从视图里抽出来是为了能脱离 SwiftUI 单独测试 —— `Model/` 不允许 import
/// SwiftUI/AppKit（仓库红线，靠 grep 保证），视图只负责把结果写进 @State。
enum Base64CodecLogic {

    /// 编辑模式
    ///
    /// 定义在这里而不是视图里，是因为「编码还是解码」是逻辑的一部分，
    /// 视图只负责把它呈现成 Picker。
    enum Mode: String, CaseIterable, Sendable {
        case encode = "编码"
        case decode = "解码"
    }

    /// 失败原因
    enum Failure: Error, Equatable {
        /// 文本无法按 UTF-8 编码（Swift String 实际上到不了这一步）
        case invalidUTF8

        /// 输入不是合法的 Base64，或解码结果不是 UTF-8 文本
        case invalidBase64
    }

    /// 编解码选项
    ///
    /// 视图从 `@AppStorage`（`base64Codec.urlSafe` / `base64Codec.wrapLines`，
    /// 与设置页同一个键）读出来后传进来，逻辑层不碰 `UserDefaults`。
    struct Options: Equatable, Sendable {
        /// URL-Safe 字母表（RFC 4648 §5）：`+/` 换成 `-_`，编码时省略尾部填充 `=`
        var isURLSafe = false
        /// 编码输出每 64 个字符折行
        var wrapsLines = false

        /// 默认行为：标准字母表、不折行
        static let standard = Options()
    }

    /// 折行宽度。RFC 2045（MIME）规定 76，这里取 64：面板宽度下 76 列会横向溢出
    private static let wrapColumn = 64

    /// 编码
    static func encode(_ input: String, options: Options = .standard) throws -> String {
        guard let data = input.data(using: .utf8) else { throw Failure.invalidUTF8 }
        var encoded = data.base64EncodedString()
        if options.isURLSafe {
            encoded = encoded.replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        }
        if options.wrapsLines {
            encoded = wrapped(encoded)
        }
        return encoded
    }

    /// 解码
    ///
    /// 两步都可能失败：Base64 本身非法，或者解出来是二进制而非文本 ——
    /// 两种对用户来说都是「无效的 Base64」，所以合成同一个错误。
    static func decode(_ input: String, options: Options = .standard) throws -> String {
        var text = input
        if options != .standard {
            // 自己产出的折行文本会被原样粘回来，空白先剥掉；URL-Safe 再归一化回标准字母表
            text = text.filter { !$0.isWhitespace }
        }
        if options.isURLSafe {
            text = text.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let remainder = text.count % 4
            if remainder > 0 {
                text += String(repeating: "=", count: 4 - remainder)
            }
        }
        guard let data = Data(base64Encoded: text),
            let decoded = String(data: data, encoding: .utf8)
        else {
            throw Failure.invalidBase64
        }
        return decoded
    }

    /// 每 64 个字符插入一个换行
    private static func wrapped(_ text: String) -> String {
        var lines: [Substring] = []
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: wrapColumn, limitedBy: text.endIndex) ?? text.endIndex
            lines.append(text[index..<end])
            index = end
        }
        return lines.joined(separator: "\n")
    }
}
