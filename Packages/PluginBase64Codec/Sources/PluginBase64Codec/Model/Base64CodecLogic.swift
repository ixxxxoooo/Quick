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

    /// 编码
    static func encode(_ input: String) throws -> String {
        guard let data = input.data(using: .utf8) else { throw Failure.invalidUTF8 }
        return data.base64EncodedString()
    }

    /// 解码
    ///
    /// 两步都可能失败：Base64 本身非法，或者解出来是二进制而非文本 ——
    /// 两种对用户来说都是「无效的 Base64」，所以合成同一个错误。
    static func decode(_ input: String) throws -> String {
        guard let data = Data(base64Encoded: input),
            let decoded = String(data: data, encoding: .utf8)
        else {
            throw Failure.invalidBase64
        }
        return decoded
    }
}
