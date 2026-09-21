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

    /// 偏好存储。注入是为了让语言档位能被测试固定住 —— 默认就是标准偏好
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 当前设置下要交给 Vision 的语言
    ///
    /// 每次识别前重新读键：设置页改了下一张截图就按新的来。
    /// internal 而不是 private：请求发给 Vision 那一步在测试里不允许跑，接线只能在这里断言。
    var configuredLanguageSettings: OCRLanguageSettings {
        OCRLanguage.settings(for: OCRPreferences.language(defaults: defaults))
    }

    /// 识别图片中的文字
    /// - Parameter image: 要识别的 CGImage
    /// - Returns: 识别出的文字（多行用换行连接）
    func recognize(image: CGImage) async -> String {
        isProcessing = true
        defer { isProcessing = false }

        let languages = configuredLanguageSettings

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // 自动检测档位交给 Vision 自己判文字体系，此时不写死候选语言；
        // 指定了语言才写，顺序即优先级（设置页承诺的是「优先」而不是「只认」）
        request.automaticallyDetectsLanguage = languages.detectsLanguageAutomatically
        if !languages.recognitionLanguages.isEmpty {
            request.recognitionLanguages = languages.recognitionLanguages
        }
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
