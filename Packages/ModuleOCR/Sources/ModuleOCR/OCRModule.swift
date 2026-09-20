// OCRModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 文字识别模块
///
/// 使用 Vision 框架从截图中识别文字。
/// 支持截取屏幕区域并自动 OCR，结果可复制或编辑。
@MainActor
public final class OCRModule: QuickModule {

    public static let id = "ocr"
    public static let name = "文字识别"
    public static let icon = "text.viewfinder"

    public var isEnabled = true

    /// OCR 引擎
    private let engine = OCREngine()

    public init() {}

    // MARK: - QuickModule 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        let triggers = ["ocr", "识别", "文字识别", "截图识别"]
        guard triggers.contains(where: { query.lowercased().contains($0) }) else { return [] }

        return [
            SearchableItem(
                id: "ocr.capture",
                moduleID: Self.id,
                title: "截图识别文字",
                subtitle: "截取屏幕区域并识别文字",
                icon: "text.viewfinder",
                relevance: 0.8,
                action: { [weak self] in
                    Task { await self?.startCapture() }
                }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(OCRResultView(engine: engine))
    }

    /// 开始截图识别
    private func startCapture() async {
        EventBus.shared.post(HidePaletteEvent(restoreFocus: false))

        // 等待面板隐藏
        try? await Task.sleep(for: .milliseconds(200))

        // 截取屏幕
        guard let image = await captureScreen() else {
            EventBus.shared.post(ShowHUDEvent(message: "截图失败", tone: .warning))
            return
        }

        // OCR 识别
        let text = await engine.recognize(image: image)

        if !text.isEmpty {
            EventBus.shared.post(CopyToClipboardEvent(text: text))
            EventBus.shared.post(ShowHUDEvent(message: "识别完成，已复制到剪贴板", tone: .success))
        } else {
            EventBus.shared.post(ShowHUDEvent(message: "未识别到文字", tone: .info))
        }
    }

    /// 截取屏幕（使用系统截图工具）
    private func captureScreen() async -> CGImage? {
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        let tempPath = NSTemporaryDirectory() + "quick_ocr_\(UUID().uuidString).png"
        task.arguments = ["-i", "-s", tempPath]

        return await withCheckedContinuation { continuation in
            task.terminationHandler = { _ in
                guard FileManager.default.fileExists(atPath: tempPath),
                      let dataProvider = CGDataProvider(url: URL(fileURLWithPath: tempPath) as CFURL),
                      let image = CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                try? FileManager.default.removeItem(atPath: tempPath)
                continuation.resume(returning: image)
            }
            try? task.run()
        }
    }
}
