// OCREngine.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics
import Vision

/// OCR 识别引擎
///
/// 使用 Vision 框架的 VNRecognizeTextRequest 进行文字识别。
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

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation]
                else {
                    continuation.resume(returning: "")
                    return
                }

                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: text)
            }

            // 配置识别参数
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja", "ko"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image)
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }
}
