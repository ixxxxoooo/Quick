// TranslationService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import NaturalLanguage

/// 翻译服务
///
/// 使用 NLLanguageRecognizer 检测语言，根据语言自动选择翻译方向。
/// 默认行为：中文 → 英文，其他语言 → 中文。
/// 语言检测以外的部分（方向判定、词表、兜底文案）都是 Model/ 里的纯逻辑，
/// 这样它们不必启动 NaturalLanguage 就能单测。
@MainActor
@Observable
final class TranslationService {

    /// 最近一次翻译结果
    private(set) var lastResult: String?

    /// 是否正在翻译中
    private(set) var isTranslating = false

    /// 检测到的源语言
    private(set) var detectedLanguage: String?

    /// 翻译文本
    /// - Parameter text: 待翻译文本
    /// - Returns: 翻译结果
    func translate(_ text: String) async -> String? {
        isTranslating = true
        defer { isTranslating = false }

        // 语言检测要用 NaturalLanguage，方向判定与查词都是纯逻辑（见 Model/）
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage
        detectedLanguage = language?.rawValue

        let direction = TranslationDirection.direction(forSourceLanguage: language?.rawValue)
        let result = TranslationDictionary.translate(text, direction: direction)
        lastResult = result
        return result
    }
}
