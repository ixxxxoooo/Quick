// TranslationService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import NaturalLanguage
import QuickCore

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

        // 两个设置都在翻译这一刻现读：设置页可以在面板开着的时候改，
        // init 时读一次就再也跟不上那个改动
        let autoDetect = PluginDefaults.isEnabled(
            PluginSettingKey.Translator.autoDetect, default: true)
        let targetLanguage = PluginDefaults.targetLanguage()

        // 「自动检测源语言」关掉时不做识别：开关的承诺就是不再识别，
        // 而识别也正是这一步唯一的环境依赖（会把文本交给 NaturalLanguage）
        var sourceLanguage: String?
        if autoDetect {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            sourceLanguage = recognizer.dominantLanguage?.rawValue
        }
        detectedLanguage = sourceLanguage

        // 方向判定与查词都是纯逻辑（见 Model/），来源与目标的取舍也放在那里
        let direction = TranslationDirection.direction(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            autoDetect: autoDetect)
        let result = TranslationDictionary.translate(text, direction: direction)
        lastResult = result
        return result
    }
}
