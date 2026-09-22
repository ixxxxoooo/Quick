// TextDiffLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 文本对比的纯逻辑
///
/// 按下标逐行对齐比较 —— 与原工具一致：第 i 行只和第 i 行比，不做 LCS 重排。
/// 代价是在中间插入一行会让其后所有行都显示为「改过」，收益是实现足够小、结果稳定可断言。
public enum TextDiffLogic {

    /// 差异结果的一行
    public struct DiffLine: Identifiable, Equatable, Sendable {

        /// 一行的差异类型
        ///
        /// 嵌在 `DiffLine` 里而不是平铺在 `TextDiffLogic` 上，是为了让调用点写
        /// `DiffLine.LineType` —— 类型跟着它描述的东西走。
        public enum LineType: Equatable, Sendable {
            case same
            case added
            case removed
        }

        /// 列表身份，只服务 SwiftUI 的 `ForEach`
        public let id = UUID()

        /// 行内容
        public let text: String

        /// 差异类型
        public let type: LineType

        public init(text: String, type: LineType) {
            self.text = text
            self.type = type
        }

        /// 只比文本和类型
        ///
        /// `id` 每次构造都是新的，把它算进相等性会让两份完全相同的对比结果永远不相等，
        /// 测试也就没法拿它做断言。
        public static func == (lhs: DiffLine, rhs: DiffLine) -> Bool {
            lhs.text == rhs.text && lhs.type == rhs.type
        }
    }

    /// 一次对比的结果
    public struct DiffResult: Equatable, Sendable {
        public let lines: [DiffLine]
        public let addedCount: Int
        public let removedCount: Int
    }

    /// 左右两栏各自的逐行状态
    ///
    /// 编辑器按行号对齐（关闭软换行 + 固定行高），所以只要给每一侧「第几行是什么状态」，
    /// 视图就能把红 / 绿底画到对应的行上。配对的规则与一维流一致：
    /// 相同行两侧都是 `.same`；某行两边内容不同时，原文档位记 `.removed`、修改后记 `.added`；
    /// 一侧没有这一行时只给有内容的那侧上色。
    public struct SideLineStates: Equatable, Sendable {
        /// 每行状态，下标即行号（0 起）
        public let left: [DiffLine.LineType]
        public let right: [DiffLine.LineType]
    }

    /// 按行位置对齐，算出左右两侧各自的逐行状态
    public static func sideLineStates(_ textA: String, against textB: String) -> SideLineStates {
        let linesA = textA.components(separatedBy: "\n")
        let linesB = textB.components(separatedBy: "\n")
        var left: [DiffLine.LineType] = []
        var right: [DiffLine.LineType] = []

        for index in 0..<max(linesA.count, linesB.count) {
            let a = index < linesA.count ? linesA[index] : nil
            let b = index < linesB.count ? linesB[index] : nil

            if a == b {
                if a != nil { left.append(.same) }
                if b != nil { right.append(.same) }
            } else {
                if a != nil { left.append(.removed) }
                if b != nil { right.append(.added) }
            }
        }
        return SideLineStates(left: left, right: right)
    }

    /// 逐行对比两段文本
    ///
    /// - Parameters:
    ///   - textA: 原文
    ///   - textB: 修改后
    /// - Returns: 对齐后的差异行与增删计数
    public static func diff(_ textA: String, against textB: String) -> DiffResult {
        let linesA = textA.components(separatedBy: "\n")
        let linesB = textB.components(separatedBy: "\n")
        var lines: [DiffLine] = []
        var added = 0
        var removed = 0

        // 行数不等时短的一侧按「没有这一行」补 nil：多出来的一行就是纯增或纯删
        for index in 0..<max(linesA.count, linesB.count) {
            let a = index < linesA.count ? linesA[index] : nil
            let b = index < linesB.count ? linesB[index] : nil

            if a == b {
                lines.append(DiffLine(text: a ?? "", type: .same))
            } else {
                // 同一行被改写时先记删除再记新增，展示顺序才和常规 diff 一致
                if let a {
                    lines.append(DiffLine(text: a, type: .removed))
                    removed += 1
                }
                if let b {
                    lines.append(DiffLine(text: b, type: .added))
                    added += 1
                }
            }
        }
        return DiffResult(lines: lines, addedCount: added, removedCount: removed)
    }

    /// 差异行的前缀符号
    public static func linePrefix(_ type: DiffLine.LineType) -> String {
        switch type {
        case .same: " "
        case .added: "+"
        case .removed: "-"
        }
    }

    /// 把差异结果渲染成可复制的文本
    public static func render(_ lines: [DiffLine]) -> String {
        lines.map { "\(linePrefix($0.type))\($0.text)" }.joined(separator: "\n")
    }
}
