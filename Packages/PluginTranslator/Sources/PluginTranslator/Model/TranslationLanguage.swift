// TranslationLanguage.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 语言选项
public struct TranslationLanguageOption: Identifiable, Sendable, Hashable {
    /// BCP-47 tag（`auto` 只用于源语言）
    public let code: String
    /// 中文名
    public let label: String
    /// 英文名
    public let englishName: String

    public var id: String { code }

    public init(code: String, label: String, englishName: String) {
        self.code = code
        self.label = label
        self.englishName = englishName
    }
}

/// 支持的语言目录
public enum TranslationLanguages {

    /// 源语言里「自动检测」的代号
    public static let autoCode = "auto"

    /// 可选语言（顺序即选择器里的顺序）
    public static let all: [TranslationLanguageOption] = [
        TranslationLanguageOption(code: "zh-Hans", label: "简体中文", englishName: "Chinese (Simplified)"),
        TranslationLanguageOption(code: "zh-Hant", label: "繁体中文", englishName: "Chinese (Traditional)"),
        TranslationLanguageOption(code: "en", label: "英语", englishName: "English"),
        TranslationLanguageOption(code: "ja", label: "日语", englishName: "Japanese"),
        TranslationLanguageOption(code: "ko", label: "韩语", englishName: "Korean"),
        TranslationLanguageOption(code: "fr", label: "法语", englishName: "French"),
        TranslationLanguageOption(code: "de", label: "德语", englishName: "German"),
        TranslationLanguageOption(code: "es", label: "西班牙语", englishName: "Spanish"),
        TranslationLanguageOption(code: "ru", label: "俄语", englishName: "Russian"),
        TranslationLanguageOption(code: "it", label: "意大利语", englishName: "Italian"),
        TranslationLanguageOption(code: "pt", label: "葡萄牙语", englishName: "Portuguese"),
        TranslationLanguageOption(code: "ar", label: "阿拉伯语", englishName: "Arabic"),
        TranslationLanguageOption(code: "th", label: "泰语", englishName: "Thai"),
        TranslationLanguageOption(code: "vi", label: "越南语", englishName: "Vietnamese")
    ]

    /// 源语言选项：自动检测 + 全部语言
    public static var sourceOptions: [TranslationLanguageOption] {
        [TranslationLanguageOption(code: autoCode, label: "自动检测", englishName: "Auto")]
            + all
    }

    /// 按 tag 找选项
    public static func option(for code: String) -> TranslationLanguageOption? {
        all.first { $0.code == code }
    }

    /// 按 tag 取中文名；未知 tag 原样返回
    public static func label(for code: String) -> String {
        if code == autoCode { return "自动检测" }
        return option(for: code)?.label ?? code
    }
}

/// 语言探测
///
/// 按书写系统判定，纯逻辑、可单测：先看假名（避免含汉字的日文被误判成中文），
/// 再看谚文、西里尔、阿拉伯、泰文，最后是 CJK，其余归英语。
/// 不做统计模型 —— 短句上统计模型反而不稳，而脚本特征在这里足够准。
public enum LanguageDetector {

    /// 探测文本语言，返回 `TranslationLanguages` 里的 tag
    public static func detect(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "en" }

        if trimmed.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) {
            return "ja"
        }
        if trimmed.unicodeScalars.contains(where: {
            (0xAC00...0xD7AF).contains($0.value) || (0x1100...0x11FF).contains($0.value)
        }) {
            return "ko"
        }
        if trimmed.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) {
            return "ru"
        }
        if trimmed.unicodeScalars.contains(where: { (0x0600...0x06FF).contains($0.value) }) {
            return "ar"
        }
        if trimmed.unicodeScalars.contains(where: { (0x0E00...0x0E7F).contains($0.value) }) {
            return "th"
        }
        if trimmed.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            return "zh-Hans"
        }
        return "en"
    }
}

/// 一次翻译实际生效的语言对
public struct EffectiveLanguages: Sendable, Equatable {
    public let source: String
    public let target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

/// 源语言 / 目标语言的取舍（对齐 Fasty `resolveEffectiveLanguages`）
public enum LanguageResolution {

    /// 由「用户选的源语言 + 目标语言 + 探测到的语言」推出实际生效的语言对
    ///
    /// 源语言选了「自动」时用探测结果；探测出的语言与目标语言相同（例如输入中文、
    /// 目标也是中文）就自动翻到另一种，避免译出原文。
    ///
    /// 探测本身（`LanguageDetector` / `NLLanguageRecognizer`）由调用方完成并传入 ——
    /// 这样取舍逻辑是纯函数，探测策略可以独立替换与测试。
    public static func effective(
        source: String,
        target: String,
        detected: String
    ) -> EffectiveLanguages {
        guard source == TranslationLanguages.autoCode else {
            return EffectiveLanguages(source: source, target: target)
        }
        if target != detected {
            return EffectiveLanguages(source: detected, target: target)
        }
        let fallback = detected.hasPrefix("zh") ? "en" : "zh-Hans"
        return EffectiveLanguages(source: detected, target: fallback)
    }

    /// 互换源语言与目标语言
    ///
    /// 源语言是「自动」时，用上一次实际生效的语言对来换 —— 否则换完还是「自动」，
    /// 用户点了交换却看不出变化。
    public static func swapped(
        source: String,
        target: String,
        effective: EffectiveLanguages?
    ) -> (source: String, target: String) {
        if source != TranslationLanguages.autoCode {
            return (source: target, target: source)
        }
        guard let effective else { return (source: target, target: source) }
        return (source: effective.target, target: effective.source)
    }
}
