// TranslationDictionary.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 翻译方向
///
/// 由源语言决定：中文出英，其余的都进中。判定只依赖语言的 BCP-47 tag，
/// 不依赖 NaturalLanguage —— 语言识别留在 TranslationService，方向判定是纯逻辑。
public enum TranslationDirection: Sendable, Equatable {

    /// 译成英文
    case toEnglish

    /// 译成简体中文
    case toChinese

    /// 目标语言的 BCP-47 tag
    public var targetCode: String {
        switch self {
        case .toEnglish: return "en"
        case .toChinese: return "zh-Hans"
        }
    }

    /// 目标语言的中文名（兜底文案里要用）
    public var targetDisplayName: String {
        switch self {
        case .toEnglish: return "英文"
        case .toChinese: return "中文"
        }
    }

    /// 从源语言 tag 推导翻译方向
    ///
    /// - Parameter code: `NLLanguage.rawValue`，识别不出语言时为 nil
    /// - Returns: 中文（简/繁）译成英文，其余（含识别不出）译成中文
    public static func direction(forSourceLanguage code: String?) -> TranslationDirection {
        switch code {
        case "zh-Hans", "zh-Hant": return .toEnglish
        default: return .toChinese
        }
    }

    /// 从设置页存的目标语言 tag 解析出目标方向
    ///
    /// 词表只有中英两向，所以只有 `zh-Hans` / `zh-Hant` / `en` 能被表达成一个方向。
    /// 设置页里还能选日语、韩语、法语、德语 —— 那四个没有任何词表支撑，这里返回 nil，
    /// 而不是硬塞成中文或英文方向：那会把结果标成一种它并没有译成的语言。
    ///
    /// - Parameter code: `PluginSettingKey.Translator.targetLang` 里存的值
    /// - Returns: 能被表达成方向的目标语言；词表表达不了或不是语言 tag 时返回 nil
    public static func target(forLanguageCode code: String?) -> TranslationDirection? {
        switch code {
        case "zh-Hans", "zh-Hant": return .toChinese
        case "en": return .toEnglish
        default: return nil
        }
    }

    /// 这次翻译往哪个方向走
    ///
    /// 优先级是「显式配置的目标语言 > 按源语言判定」：用户在设置页选过的目标不该被
    /// 识别结果盖掉，否则那个选择器就成了摆设。
    ///
    /// `autoDetect` 关闭时调用方根本不做语言识别（`sourceLanguage` 只会是 nil），
    /// 方向因此只由目标语言决定；若目标语言又恰好是词表表达不了的那四个，
    /// 这里退回 `direction(forSourceLanguage: nil)`，即译成中文。
    ///
    /// - Parameters:
    ///   - sourceLanguage: 识别出的源语言，未识别或未开启识别时为 nil
    ///   - targetLanguage: 设置页配置的目标语言 tag
    ///   - autoDetect: 设置页的「自动检测源语言」
    /// - Returns: 本次要用的翻译方向
    public static func direction(
        sourceLanguage: String?,
        targetLanguage: String?,
        autoDetect: Bool
    ) -> TranslationDirection {
        if let configured = target(forLanguageCode: targetLanguage) { return configured }
        return direction(forSourceLanguage: autoDetect ? sourceLanguage : nil)
    }
}

/// 内置简易中英词典
///
/// 真正的翻译能力尚未接入，这一层先用固定词表顶上。词表的键统一小写，
/// 所以查表前必须把输入也折成小写，否则 `Hello` / `HELLO` 都查不到 `hello`。
public enum TranslationDictionary {

    /// 固定词表（键为小写）
    public static let entries: [String: String] = [
        "你好": "Hello",
        "谢谢": "Thank you",
        "再见": "Goodbye",
        "hello": "你好",
        "thank you": "谢谢",
        "goodbye": "再见"
    ]

    /// 查词（大小写不敏感）
    ///
    /// - Parameter text: 待查文本
    /// - Returns: 命中的译文；词表里没有则返回 nil
    public static func lookup(_ text: String) -> String? {
        entries[text.lowercased()]
    }

    /// 词表外的兜底文案
    ///
    /// 用目标语言标注，避免把「没翻出来」误当成译文。
    ///
    /// - Parameters:
    ///   - text: 原文
    ///   - direction: 翻译方向
    /// - Returns: 形如 `[中文翻译] 原文` 的占位结果
    public static func fallback(_ text: String, direction: TranslationDirection) -> String {
        "[\(direction.targetDisplayName)翻译] \(text)"
    }

    /// 翻译：先查词，查不到走兜底
    ///
    /// - Parameters:
    ///   - text: 待翻译文本
    ///   - direction: 翻译方向
    /// - Returns: 译文或兜底文案（永不为 nil）
    public static func translate(_ text: String, direction: TranslationDirection) -> String {
        lookup(text) ?? fallback(text, direction: direction)
    }
}
