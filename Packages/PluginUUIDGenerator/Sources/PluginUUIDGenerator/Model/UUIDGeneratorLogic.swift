// UUIDGeneratorLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// UUID 生成的纯逻辑
///
/// 视图只负责持有 `@State`，数量/大小写/连字符的处理集中在这里 ——
/// `Model/` 里禁止出现任何 UI 框架，因此这块逻辑能被测试独立验证。
enum UUIDGeneratorLogic {

    /// UUID 版本
    enum Version: String, CaseIterable, Sendable {
        /// 纯随机（RFC 9562 §5.4）
        case v4 = "v4"
        /// 时间有序：高 48 位是毫秒时间戳，做数据库主键时索引局部性好（RFC 9562 §5.7）
        case v7 = "v7"
    }

    /// 构造一个 v7 UUID
    ///
    /// - Parameters:
    ///   - milliseconds: Unix 毫秒时间戳，只取低 48 位
    ///   - random: 10 个随机字节，只取前 10 个；不足时补 0
    /// 布局：48 位时间戳 | 4 位版本(0111) | 12 位随机 | 2 位变体(10) | 62 位随机
    static func makeV7(milliseconds: UInt64, random: [UInt8]) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<6 {
            bytes[index] = UInt8((milliseconds >> UInt64(8 * (5 - index))) & 0xFF)
        }
        for index in 0..<10 {
            bytes[6 + index] = index < random.count ? random[index] : 0
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// 生成一批 v7 UUID，保证批内严格按生成顺序递增
    ///
    /// 同一毫秒里连续生成时，后一个的时间戳顺延 1ms（`max(now, previous + 1)`）。
    /// 否则同毫秒的几个值只靠随机位排序，复制出去的一批 ID 会「看起来乱序」，
    /// 而时间有序正是用 v7 的理由。
    static func generateV7(
        count: Int,
        now: Date = Date(),
        randomBytes: () -> [UInt8] = { (0..<10).map { _ in UInt8.random(in: .min ... .max) } }
    ) -> [UUID] {
        var previous: UInt64 = 0
        let base = UInt64(max(0, now.timeIntervalSince1970 * 1000))
        return (0..<max(0, count)).map { _ in
            let stamp = max(base, previous &+ 1)
            previous = stamp
            return makeV7(milliseconds: stamp, random: randomBytes())
        }
    }

    /// 生成一批 UUID 字符串
    ///
    /// - Parameters:
    ///   - count: 要生成的数量。小于 0 按 0 处理，避免 `0..<count` 直接崩掉。
    ///   - uppercase: 是否大写。`UUID.uuidString` 本身是大写，
    ///     所以关掉它才是要做一次额外转换，保持和原来一致的语义。
    ///   - removeDashes: 是否去掉连字符（32 位紧凑形式）。
    ///   - version: UUID 版本。`.v7` 时忽略 `generator`，由 `generateV7` 产出。
    ///   - generator: v4 的 UUID 来源。默认取系统随机源；
    ///     测试传入固定值即可对输出做断言，不必去猜随机结果。
    /// - Returns: 按生成顺序排列的字符串
    static func generate(
        count: Int,
        uppercase: Bool,
        removeDashes: Bool,
        version: Version = .v4,
        using generator: () -> UUID = { UUID() }
    ) -> [String] {
        let source: [UUID]
        switch version {
        case .v4: source = (0..<max(0, count)).map { _ in generator() }
        case .v7: source = generateV7(count: count)
        }
        return source.map { uuid in
            var text = uuid.uuidString
            if !uppercase { text = text.lowercased() }
            if removeDashes { text = text.replacingOccurrences(of: "-", with: "") }
            return text
        }
    }
}
