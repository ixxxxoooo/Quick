// TranslationService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import NaturalLanguage

/// 翻译服务
///
/// 使用 NLLanguageRecognizer 检测语言，根据语言自动选择翻译方向。
/// 默认行为：中文 → 英文，其他语言 → 中文。
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

        // 检测语言
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage
        detectedLanguage = language?.rawValue

        // 确定翻译方向
        let isChinese = language == .simplifiedChinese || language == .traditionalChinese
        let targetLang = isChinese ? "en" : "zh-Hans"

        // 使用系统翻译 API（macOS 26 提供原生 Translation 框架）
        // 这里使用备用方案：调用系统词典
        let result = await translateWithDictionary(text: text, targetLang: targetLang)
        lastResult = result
        return result
    }

    /// 使用系统服务进行翻译（备用方案）
    private func translateWithDictionary(text: String, targetLang: String) async -> String? {
        // 使用 NSLinguisticTagger 进行基础词汇翻译
        // 完整翻译需要集成 Translation 框架或第三方 API
        // 这里提供框架接口，实际翻译能力可通过后续集成增强

        // 简单的中英互译词典（示例）
        let simpleDict: [String: String] = [
            "你好": "Hello",
            "谢谢": "Thank you",
            "再见": "Goodbye",
            "hello": "你好",
            "thank you": "谢谢",
            "goodbye": "再见",
        ]

        if let simple = simpleDict[text.lowercased()] {
            return simple
        }

        // 对于更复杂的翻译，返回提示信息
        return "[\(targetLang == "en" ? "英文" : "中文")翻译] \(text)"
    }
}
