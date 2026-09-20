// WordCounterLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 字数统计的纯逻辑
///
/// 所有计数规则集中在这里，视图只负责把 `Stats` 摆到卡片上。
/// 规则本身没有环境依赖（不读时钟、不读文件系统），所以可以直接断言。
public enum WordCounterLogic {

    /// 一次统计的全部指标
    public struct Stats: Equatable, Sendable {

        /// 字符数（按扩展字形簇计数，emoji / 组合字符算一个）
        public let characterCount: Int

        /// 去掉所有空白（含换行）后的字符数
        public let characterCountNoSpaces: Int

        /// 单词数：按空白切分后的片段数
        public let wordCount: Int

        /// 行数：空文本算 0 行
        public let lineCount: Int

        /// UTF-8 字节数
        public let byteCount: Int

        /// 中文表意文字个数
        public let chineseCount: Int

        /// 拉丁字母个数
        public let englishCount: Int

        /// 数字字符个数
        public let digitCount: Int

        /// 标点符号个数
        public let punctuationCount: Int

        /// 预估阅读时长（分钟）
        public let readingMinutes: Int

        /// 阅读时长的展示文本
        public var readingTime: String { "约 \(readingMinutes) 分钟" }
    }

    /// 中文阅读速度（字/分钟）
    private static let charactersPerMinute = 500

    /// 统计一段文本
    ///
    /// - Parameter text: 待统计的文本
    /// - Returns: 全部指标
    public static func stats(for text: String) -> Stats {
        let noSpaces = text.filter { !$0.isWhitespace }.count
        return Stats(
            characterCount: text.count,
            characterCountNoSpaces: noSpaces,
            wordCount: text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count,
            lineCount: text.isEmpty ? 0 : text.components(separatedBy: "\n").count,
            byteCount: text.utf8.count,
            chineseCount: text.filter { $0.isChineseCharacter }.count,
            englishCount: text.filter { $0.isASCII && $0.isLetter }.count,
            digitCount: text.filter { $0.isNumber }.count,
            punctuationCount: text.filter { $0.isPunctuation }.count,
            // 下限 1 分钟：宁可显示「约 1 分钟」也不要「约 0 分钟」
            readingMinutes: max(1, noSpaces / charactersPerMinute)
        )
    }
}

// MARK: - Character 扩展

extension Character {

    /// 是否是中日韩表意文字
    ///
    /// 只认基本区和扩展 A，与原工具一致 —— 扩展 B 及以上的生僻字不计入中文。
    var isChineseCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
            || (0x3400...0x4DBF).contains(scalar.value)
    }
}
