// JSONTree.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreFoundation
import Foundation

/// 解析后的 JSON 节点树
///
/// Foundation / CoreFoundation only（`Model/` 不允许引入 SwiftUI、AppKit）。树视图只消费它，
/// 不做任何解析 —— 解析只有 `JSONFormatterLogic` 一处。
public indirect enum JSONNode: Equatable, Sendable {

    case object([Pair])
    case array([JSONNode])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    /// 对象里的一个键值对
    public struct Pair: Equatable, Sendable {
        public let key: String
        public let value: JSONNode

        public init(key: String, value: JSONNode) {
            self.key = key
            self.value = value
        }
    }

    /// 是不是「能展开」的容器
    public var isContainer: Bool {
        switch self {
        case .object, .array: true
        default: false
        }
    }

    /// 容器里的直接子节点数；叶子为 0
    public var childCount: Int {
        switch self {
        case .object(let pairs): pairs.count
        case .array(let items): items.count
        default: 0
        }
    }

    /// 展示用的类型
    public var kind: JSONTreeRow.Kind {
        switch self {
        case .object: .object
        case .array: .array
        case .string: .string
        case .number: .number
        case .bool: .bool
        case .null: .null
        }
    }

    /// 节点总数（容器算一个，叶子各算一个）
    public var nodeCount: Int {
        switch self {
        case .object(let pairs): 1 + pairs.reduce(0) { $0 + $1.value.nodeCount }
        case .array(let items): 1 + items.reduce(0) { $0 + $1.nodeCount }
        default: 1
        }
    }

    /// 紧凑 JSON 文本（复制整棵子树时用）
    public func compactText() -> String {
        switch self {
        case .object(let pairs):
            "{" + pairs.map { "\"\(Self.escape($0.key))\":\($0.value.compactText())" }.joined(separator: ",")
                + "}"
        case .array(let items):
            "[" + items.map { $0.compactText() }.joined(separator: ",") + "]"
        case .string(let value):
            "\"\(Self.escape(value))\""
        case .number(let value):
            Self.numberText(value)
        case .bool(let value):
            value ? "true" : "false"
        case .null:
            "null"
        }
    }

    /// 叶子值在树里的预览（字符串带引号、控制字符转义成可见形式）
    func leafPreview() -> String {
        switch self {
        case .string(let value): "\"\(Self.escapePreview(value))\""
        case .number(let value): Self.numberText(value)
        case .bool(let value): value ? "true" : "false"
        case .null: "null"
        case .object(let pairs): "{\(pairs.count)}"
        case .array(let items): "[\(items.count)]"
        }
    }

    /// 复制叶子时给的内容（字符串去掉引号，其余就是字面量）
    var copyText: String {
        if case .string(let value) = self { return value }
        return leafPreview()
    }

    static func numberText(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
            return String(Int64(value))
        }
        return String(value)
    }

    static func escape(_ value: String) -> String {
        var out = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    /// 预览用：把控制字符转成可见的转义，并压平成单行
    static func escapePreview(_ value: String) -> String {
        escape(value)
    }
}

// MARK: - 树的一行

/// 树里可见的一行
public struct JSONTreeRow: Identifiable, Equatable, Sendable {

    public enum Kind: Equatable, Sendable {
        case object, array, string, number, bool, null
    }

    /// 稳定标识：从根算起的路径（`$.a[0]`）
    public let id: String

    /// 层级（根为 0）
    public let depth: Int

    /// 对象里的键；数组元素与根为 `nil`
    public let key: String?

    /// 展示文本：容器是 `{n}` / `[n]`，叶子是值的预览
    public let value: String

    public let kind: Kind
    public let isContainer: Bool
    public let isCollapsed: Bool

    /// 这一行自身命中搜索词（键或叶子值）
    public let matchesQuery: Bool

    /// 复制这一行（容器是整棵子树的紧凑 JSON）
    public let copyText: String
}

// MARK: - 布局

/// 把节点树拍平成可见行
///
/// 拍平而不是递归视图：`LazyVStack` 只渲染可见行，深/大的 JSON 才不会卡。
/// 折叠状态用「路径集合」表示，搜索命中时自动展开命中路径（与 JSON Viewer 一致）。
public enum JSONTreeLayout {

    /// 默认折叠状态：只展开根，其余容器收起成 `{n}` / `[n]`
    public static func defaultCollapsed(_ root: JSONNode) -> Set<String> {
        var collapsed: Set<String> = []
        collectContainers(root, path: "$", depth: 0, into: &collapsed)
        return collapsed
    }

    /// 全部折叠（连根一起），只留一行 `{n}` / `[n]`
    public static func allCollapsed(_ root: JSONNode) -> Set<String> {
        var collapsed = defaultCollapsed(root)
        if root.isContainer { collapsed.insert("$") }
        return collapsed
    }

    /// 生成可见行
    ///
    /// - Parameters:
    ///   - root: 节点树
    ///   - collapsed: 被折叠的容器路径
    ///   - query: 搜索词；命中时对应路径强制展开
    public static func rows(root: JSONNode, collapsed: Set<String>, query: String) -> [JSONTreeRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var rows: [JSONTreeRow] = []
        _ = build(
            root,
            key: nil,
            path: "$",
            depth: 0,
            query: trimmed,
            collapsed: collapsed,
            into: &rows
        )
        return rows
    }

    // MARK: - 内部

    private static func collectContainers(
        _ node: JSONNode, path: String, depth: Int, into collapsed: inout Set<String>
    ) {
        guard node.isContainer else { return }
        if depth > 0 { collapsed.insert(path) }
        switch node {
        case .object(let pairs):
            for pair in pairs {
                collectContainers(
                    pair.value, path: objectChild(path, key: pair.key), depth: depth + 1, into: &collapsed)
            }
        case .array(let items):
            for (index, item) in items.enumerated() {
                collectContainers(item, path: "\(path)[\(index)]", depth: depth + 1, into: &collapsed)
            }
        default:
            break
        }
    }

    /// - Returns: 该子树（含自身）是否命中查询
    @discardableResult
    private static func build(
        _ node: JSONNode,
        key: String?,
        path: String,
        depth: Int,
        query: String,
        collapsed: Set<String>,
        into rows: inout [JSONTreeRow]
    ) -> Bool {
        let hasQuery = !query.isEmpty
        let selfMatches = hasQuery && matches(node, key: key, query: query)
        let collapsedHere = collapsed.contains(path)

        guard node.isContainer else {
            rows.append(
                JSONTreeRow(
                    id: path,
                    depth: depth,
                    key: key,
                    value: node.leafPreview(),
                    kind: node.kind,
                    isContainer: false,
                    isCollapsed: false,
                    matchesQuery: selfMatches,
                    copyText: node.copyText
                ))
            return selfMatches
        }

        // 没在搜索又折叠着，就不用往下走
        if !hasQuery, collapsedHere {
            rows.append(
                containerRow(node, key: key, path: path, depth: depth, matches: false, collapsed: true))
            return false
        }

        var children: [JSONTreeRow] = []
        var childMatches = false
        switch node {
        case .object(let pairs):
            for pair in pairs {
                let childPath = objectChild(path, key: pair.key)
                let matched = build(
                    pair.value, key: pair.key, path: childPath, depth: depth + 1,
                    query: query, collapsed: collapsed, into: &children)
                childMatches = childMatches || matched
            }
        case .array(let items):
            for (index, item) in items.enumerated() {
                let matched = build(
                    item, key: nil, path: "\(path)[\(index)]", depth: depth + 1,
                    query: query, collapsed: collapsed, into: &children)
                childMatches = childMatches || matched
            }
        default:
            break
        }

        let expanded = childMatches || !collapsedHere
        rows.append(
            containerRow(node, key: key, path: path, depth: depth, matches: selfMatches, collapsed: !expanded)
        )
        if expanded { rows.append(contentsOf: children) }
        return selfMatches || childMatches
    }

    private static func containerRow(
        _ node: JSONNode, key: String?, path: String, depth: Int, matches: Bool, collapsed: Bool
    ) -> JSONTreeRow {
        JSONTreeRow(
            id: path,
            depth: depth,
            key: key,
            value: collapsed ? (node.kind == .array ? "[\(node.childCount)]" : "{\(node.childCount)}") : "",
            kind: node.kind,
            isContainer: true,
            isCollapsed: collapsed,
            matchesQuery: matches,
            copyText: node.compactText()
        )
    }

    private static func matches(_ node: JSONNode, key: String?, query: String) -> Bool {
        if let key, key.localizedCaseInsensitiveContains(query) { return true }
        if !node.isContainer, node.leafPreview().localizedCaseInsensitiveContains(query) { return true }
        return false
    }

    private static func objectChild(_ path: String, key: String) -> String {
        "\(path)[\"\(JSONNode.escape(key))\"]"
    }
}
