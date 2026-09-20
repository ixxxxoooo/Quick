// JSONFormatterLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// JSON 格式化的纯逻辑
///
/// 从视图里抽出来是为了能脱离 SwiftUI 单独测试 —— `Model/` 不允许 import
/// SwiftUI/AppKit（仓库红线，靠 grep 保证），视图只负责把结果写进 @State。
enum JSONFormatterLogic {

    /// 格式化结果
    struct Outcome: Equatable, Sendable {
        /// 格式化后的文本
        let text: String

        /// JSON 节点总数（字典/数组算一个节点，叶子值算一个）
        let nodeCount: Int
    }

    /// 失败原因
    enum Failure: Error, Equatable {
        /// 输入不是可解析的 JSON
        case invalidJSON
    }

    /// 美化输出
    ///
    /// JSONSerialization 只肯输出 2 空格缩进，4 空格只能靠文本替换 ——
    /// 这是它唯一能改缩进的手段，所以不要换成别的写法。
    static func prettyPrint(_ input: String, indent: Int) throws -> Outcome {
        let json = try parse(input)
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        guard let formatted = try? JSONSerialization.data(withJSONObject: json, options: options),
            let text = String(data: formatted, encoding: .utf8)
        else {
            throw Failure.invalidJSON
        }
        return Outcome(
            text: indent == 4 ? text.replacingOccurrences(of: "  ", with: "    ") : text,
            nodeCount: countNodes(json)
        )
    }

    /// 压缩输出
    ///
    /// 与美化共用 `.sortedKeys`，保证同一份 JSON 的两种输出键序一致。
    static func minify(_ input: String) throws -> String {
        let json = try parse(input)
        guard let compacted = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
            let text = String(data: compacted, encoding: .utf8)
        else {
            throw Failure.invalidJSON
        }
        return text
    }

    /// 人类可读的字节数
    static func byteSize(_ text: String) -> String {
        let bytes = text.utf8.count
        if bytes < 1024 { return "\(bytes) B" }
        return String(format: "%.1f KB", Double(bytes) / 1024)
    }

    // MARK: - 内部

    /// 解析为 JSON 对象树
    ///
    /// 顶层片段（裸字符串/数字）在没有 `.fragmentsAllowed` 时解析失败 ——
    /// 这里刻意保留默认行为，与视图原来的表现一致。
    private static func parse(_ input: String) throws -> Any {
        guard let data = input.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data)
        else {
            throw Failure.invalidJSON
        }
        return json
    }

    private static func countNodes(_ obj: Any) -> Int {
        if let dict = obj as? [String: Any] {
            return 1 + dict.values.reduce(0) { $0 + countNodes($1) }
        }
        if let arr = obj as? [Any] {
            return 1 + arr.reduce(0) { $0 + countNodes($1) }
        }
        return 1
    }
}
