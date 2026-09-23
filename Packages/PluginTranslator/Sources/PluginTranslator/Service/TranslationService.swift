// TranslationService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import NaturalLanguage
import Observation
import Translation

/// 一次翻译的结果
struct TranslationOutcome: Sendable {
    let result: String
    let effective: EffectiveLanguages
    /// 探测到的源语言（未探测时为 nil）
    let detectedSource: String?
}

/// 翻译失败的原因
enum TranslationError: LocalizedError {
    /// 语言对受支持但语言包还没下载
    case notInstalled(EffectiveLanguages)
    /// 系统不支持这个语言对
    case unsupportedPair(EffectiveLanguages)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let pair):
            return
                "\(TranslationLanguages.label(for: pair.source)) → \(TranslationLanguages.label(for: pair.target)) 的语言包还没下载。请到「系统设置 › 通用 › 语言与地区 › 翻译语言」下载后重试。"
        case .unsupportedPair(let pair):
            return
                "系统暂不支持 \(TranslationLanguages.label(for: pair.source)) → \(TranslationLanguages.label(for: pair.target)) 的翻译。"
        }
    }
}

/// 翻译服务
///
/// 走 Apple 的 `Translation` 框架做**端上翻译**（不联网、不出本机）。语言探测用
/// `NLLanguageRecognizer`，语言对取舍是 Model/ 里的纯逻辑。
///
/// 两种用法：
/// - `requestTranslation(...)`：给视图用，取消上一次、异步更新可观察状态；
/// - `translateOnce(...)`：给主面板内联结果用，直接返回结果、不碰状态。
@MainActor
@Observable
final class TranslationService {

    /// 最近一次译文
    private(set) var result = ""
    /// 是否正在翻译
    private(set) var isTranslating = false
    /// 失败原因（成功时为 nil）
    private(set) var errorMessage: String?
    /// 探测到的源语言
    private(set) var detectedLanguage: String?
    /// 最近一次实际生效的语言对
    private(set) var effective = EffectiveLanguages(source: "en", target: "zh-Hans")

    private var currentTask: Task<Void, Never>?

    /// 取消正在进行的翻译
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isTranslating = false
    }

    /// 视图入口：取消上一次请求，异步翻译并更新状态
    func requestTranslation(text: String, source: String, target: String) {
        currentTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            result = ""
            errorMessage = nil
            isTranslating = false
            return
        }

        isTranslating = true
        errorMessage = nil
        currentTask = Task { [weak self] in
            do {
                let outcome = try await Self.perform(trimmed, source: source, target: target)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.result = outcome.result
                self.effective = outcome.effective
                self.detectedLanguage = outcome.detectedSource
                self.errorMessage = nil
                self.isTranslating = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.result = ""
                self.errorMessage =
                    (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                self.isTranslating = false
            }
        }
    }

    /// 内联入口：不碰可观察状态，直接返回结果
    func translateOnce(
        _ text: String, source: String, target: String
    ) async throws
        -> TranslationOutcome
    {
        try await Self.perform(
            text.trimmingCharacters(in: .whitespacesAndNewlines), source: source, target: target)
    }

    // MARK: - 内部

    /// 真正干活的一步
    ///
    /// `nonisolated static`：`TranslationSession` 不是 `Sendable`，把它放在主 actor 上、
    /// 再 `await` 它的方法会触发「跨隔离域传递」的编译错误。会话只在这个函数内部创建与使用，
    /// 不跨任何隔离域，于是不需要（也不该）缓存它 —— 框架自己会复用底层资源。
    private nonisolated static func perform(
        _ text: String, source: String, target: String
    ) async throws
        -> TranslationOutcome
    {
        let detected = Self.detectCode(text)
        let pair = LanguageResolution.effective(source: source, target: target, detected: detected)

        let availability = LanguageAvailability()
        let status = await availability.status(
            from: Locale.Language(identifier: pair.source),
            to: Locale.Language(identifier: pair.target)
        )
        switch status {
        case .installed:
            let session = TranslationSession(
                installedSource: Locale.Language(identifier: pair.source),
                target: Locale.Language(identifier: pair.target)
            )
            let response = try await session.translate(text)
            return TranslationOutcome(
                result: response.targetText,
                effective: pair,
                detectedSource: detected
            )
        case .supported:
            throw TranslationError.notInstalled(pair)
        default:
            throw TranslationError.unsupportedPair(pair)
        }
    }

    /// 探测文本语言并映射到 `TranslationLanguages` 的 tag
    nonisolated static func detectCode(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else {
            return LanguageDetector.detect(text)
        }
        return code(for: language)
    }

    nonisolated private static func code(for language: NLLanguage) -> String {
        switch language {
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .english: return "en"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .french: return "fr"
        case .german: return "de"
        case .spanish: return "es"
        case .russian: return "ru"
        case .italian: return "it"
        case .portuguese: return "pt"
        case .arabic: return "ar"
        case .thai: return "th"
        case .vietnamese: return "vi"
        default:
            let raw = language.rawValue
            return raw.isEmpty ? LanguageDetector.detect(raw) : raw
        }
    }
}
