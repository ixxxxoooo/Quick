// UUIDGeneratorLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// UUID 生成的纯逻辑
///
/// 视图只负责持有 `@State`，数量/大小写/连字符的处理集中在这里 ——
/// `Model/` 里禁止出现任何 UI 框架，因此这块逻辑能被测试独立验证。
enum UUIDGeneratorLogic {

    /// 生成一批 UUID 字符串
    ///
    /// - Parameters:
    ///   - count: 要生成的数量。小于 0 按 0 处理，避免 `0..<count` 直接崩掉。
    ///   - uppercase: 是否大写。`UUID.uuidString` 本身是大写，
    ///     所以关掉它才是要做一次额外转换，保持和原来一致的语义。
    ///   - removeDashes: 是否去掉连字符（32 位紧凑形式）。
    ///   - generator: UUID 来源。默认取系统随机源；
    ///     测试传入固定值即可对输出做断言，不必去猜随机结果。
    /// - Returns: 按生成顺序排列的字符串
    static func generate(
        count: Int,
        uppercase: Bool,
        removeDashes: Bool,
        using generator: () -> UUID = { UUID() }
    ) -> [String] {
        (0..<max(0, count)).map { _ in
            var text = generator().uuidString
            if !uppercase { text = text.lowercased() }
            if removeDashes { text = text.replacingOccurrences(of: "-", with: "") }
            return text
        }
    }
}
