// OCREngine.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics
import Foundation
import Vision

/// OCR 识别引擎
///
/// 使用 Vision 框架的 RecognizeTextRequest 进行文字识别。
/// 支持中文、英文及多语言混合识别。
@MainActor
@Observable
final class OCREngine {

    /// 最近一次识别结果
    private(set) var lastResult: String = ""

    /// 是否正在识别中
    private(set) var isProcessing = false

    /// 识别图片中的文字
    /// - Parameter image: 要识别的 CGImage
    /// - Returns: 识别出的文字（多行用换行连接）
    func recognize(image: CGImage) async -> String {
        isProcessing = true
        defer { isProcessing = false }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "zh-Hant"),
            Locale.Language(identifier: "en-US"),
            Locale.Language(identifier: "ja"),
            Locale.Language(identifier: "ko")
        ]
        request.usesLanguageCorrection = true

        // 现代 Vision 异步 API：perform 会在后台执行，完成后回到 MainActor，
        // 不再需要 DispatchQueue + continuation 桥接，也就不会踩到隔离校验。
        let handler = ImageRequestHandler(image)
        guard let observations = try? await handler.perform(request) else {
            lastResult = ""
            return ""
        }

        // 拼装规则是纯逻辑，放在模型层（见 OCRText）
        let text = OCRText.joined(observations.map(\.transcript))
        lastResult = text
        return text
    }
}
