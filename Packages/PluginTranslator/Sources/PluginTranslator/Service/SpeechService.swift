// SpeechService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AVFoundation
import Foundation

/// 朗读服务
///
/// 用系统 `AVSpeechSynthesizer` 朗读原文 / 译文 / 单词发音 —— 端上合成、不需要联网，
/// 也不依赖词典的音频链接。按语言选系统语音；没有对应语音时退回默认语音。
@MainActor
final class SpeechService {

    private let synthesizer = AVSpeechSynthesizer()

    /// 是否正在朗读
    var isSpeaking: Bool { synthesizer.isSpeaking }

    /// 朗读一段文本
    ///
    /// - Parameters:
    ///   - text: 待朗读文本
    ///   - language: `TranslationLanguages` 里的 tag
    func speak(_ text: String, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        if let voice = AVSpeechSynthesisVoice(language: Self.voiceLanguage(for: language)) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    /// 停止朗读
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// 把 `TranslationLanguages` 的 tag 映射到语音标识
    static func voiceLanguage(for code: String) -> String {
        switch code {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "en": return "en-US"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "es": return "es-ES"
        case "ru": return "ru-RU"
        case "it": return "it-IT"
        case "pt": return "pt-PT"
        case "ar": return "ar-SA"
        case "th": return "th-TH"
        case "vi": return "vi-VN"
        default: return code
        }
    }
}
