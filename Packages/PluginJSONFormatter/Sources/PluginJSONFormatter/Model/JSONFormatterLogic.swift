// JSONFormatterLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreFoundation
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
    /// JSONSerialization 只肯输出 2 空格缩进，4 空格只能把每行的行首缩进翻倍 ——
    /// 字符串值里的换行已被转义成 `\n`，真实换行只可能是结构性的，所以行首空格
    /// 一定是缩进；绝不能做全局替换，那会改掉字符串值内部的空格。
    static func prettyPrint(_ input: String, indent: Int) throws -> Outcome {
        let json = try parse(input)
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        guard let formatted = try? JSONSerialization.data(withJSONObject: json, options: options),
            let text = String(data: formatted, encoding: .utf8)
        else {
            throw Failure.invalidJSON
        }
        return Outcome(
            text: indent == 4 ? doublingLeadingIndentation(text) : text,
            nodeCount: countNodes(json)
        )
    }

    /// 把每行的行首空格数翻倍（2 空格缩进 → 4 空格缩进）
    private static func doublingLeadingIndentation(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { line in
            guard let firstMeaningful = line.firstIndex(where: { $0 != " " }) else { return line }
            let depth = line.distance(from: line.startIndex, to: firstMeaningful)
            return String(repeating: " ", count: depth * 2) + line[firstMeaningful...]
        }.joined(separator: "\n")
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

    // MARK: - 树

    /// 解析成节点树（树视图用）
    static func parseTree(_ input: String) throws -> JSONNode {
        node(from: try parse(input))
    }

    // MARK: - 反转义

    /// 把「被转义的 JSON 字符串」还原成正常文本
    ///
    /// 覆盖两种常见来源：
    /// - 整段带引号的 JSON 字符串字面量（`"{\"a\":1}"`），按 JSON 字符串解码；
    /// - 裸的转义正文（`{\"a\":1,\n\"b\":2}`），补一层引号再解码。
    ///
    /// 只解一层。多重转义（`\\\"`）需要用户再点一次 —— 盲目递归会把本该保留的
    /// 转义也吃掉。
    static func unescape(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.invalidJSON }

        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            if let decoded = decodeJSONString(trimmed) { return decoded }
        }
        if let decoded = decodeJSONString("\"\(trimmed)\"") { return decoded }
        throw Failure.invalidJSON
    }

    /// 自动反转义：只在「当前不是合法 JSON、但反转义之后是合法 JSON」时才还原
    ///
    /// 这样既不会改动用户正在写的正常 JSON，也不会把普通文本误当成转义内容。
    // MARK: - 一次性分析

    /// 超过它就不再构建节点树：树要为每个节点分配对象，几 MB 的 JSON 会占用大量内存与时间。
    /// 体积更大的文本仍会校验合法性，只是树视图不可用。
    static let treeParseLimit = 512 * 1024

    /// 一次分析的结果：编辑器每次文本变化只需要这一份
    struct Analysis: Sendable, Equatable {
        /// 自动反转义后的文本（与输入相同表示不需要改写）
        let text: String
        /// 节点树；非法、为空或体积超限时为 `nil`
        let root: JSONNode?
        /// 文本为空白
        let isBlank: Bool
        /// 是合法 JSON
        let isValid: Bool
        /// 因体积超限而跳过了树
        let treeSkipped: Bool
    }

    /// 反转义 + 校验 + 建树合并成一次分析
    ///
    /// 以前每次按键要做两遍完整解析（`autoUnescape` 一遍、`parseTree` 一遍），
    /// 现在是纯函数、可放到后台线程，并且体积超限时只做校验不建树。
    static func analyze(_ input: String) -> Analysis {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Analysis(text: input, root: nil, isBlank: true, isValid: false, treeSkipped: false)
        }
        // 与 `autoUnescape` 同一规则（原文合法就不动；否则反转义后合法才采用），
        // 但把解析结果直接复用，合法输入只解析一遍
        var text = input
        var parsed = try? parse(input)
        if parsed == nil, let decoded = try? unescape(input), let reparsed = try? parse(decoded) {
            text = decoded
            parsed = reparsed
        }
        guard let parsed else {
            return Analysis(text: text, root: nil, isBlank: false, isValid: false, treeSkipped: false)
        }
        if text.utf8.count > treeParseLimit {
            return Analysis(text: text, root: nil, isBlank: false, isValid: true, treeSkipped: true)
        }
        return Analysis(text: text, root: node(from: parsed), isBlank: false, isValid: true, treeSkipped: false)
    }

    static func autoUnescape(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        if (try? parse(input)) != nil { return input }
        guard let decoded = try? unescape(input), (try? parse(decoded)) != nil else { return input }
        return decoded
    }

    /// 把一段 JSON 字符串字面量解码成它表示的内容，失败返回 nil
    private static func decodeJSONString(_ literal: String) -> String? {
        guard let data = literal.data(using: .utf8),
            let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
            let string = value as? String
        else {
            return nil
        }
        return string
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

    /// `JSONSerialization` 的对象树 → `JSONNode`
    ///
    /// **键排序一次。** 否则同一份 JSON 每次生成的树顺序不同，折叠状态（按路径存）
    /// 也会跟着错位。布尔与数字都是 `NSNumber`，靠 CFTypeID 区分。
    private static func node(from any: Any) -> JSONNode {
        if let dict = any as? [String: Any] {
            return .object(
                dict.keys.sorted().map { JSONNode.Pair(key: $0, value: node(from: dict[$0]!)) })
        }
        if let arr = any as? [Any] {
            return .array(arr.map(node(from:)))
        }
        if let string = any as? String { return .string(string) }
        if let number = any as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            return .number(number.doubleValue)
        }
        return .null
    }
}
