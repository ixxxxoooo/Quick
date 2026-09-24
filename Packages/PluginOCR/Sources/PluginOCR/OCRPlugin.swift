// OCRPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 文字识别插件
///
/// 使用 Vision 框架从截图中识别文字。
/// 支持截取屏幕区域并自动 OCR，结果可复制或编辑。
@MainActor
public final class OCRPlugin: QuickPlugin, PluginViewProviding {

    public static let id = "ocr"
    public static let name = "文字识别"
    public static let icon = "doc.text.viewfinder"
    public static let description = "基于 Apple Vision 原生离线光学字符识别，选取屏幕区域即可快速提取文字并自动复制到剪贴板。"
    public static let triggerWords = OCRQuery.triggers

    public var isEnabled = true

    private let log = QuickLog.plugin(OCRPlugin.id)

    /// OCR 引擎
    private let engine = OCREngine()

    public init() {}

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "ocr.capture",
                pluginID: id,
                pluginName: name,
                title: "截图识别文字",
                subtitle: "截取屏幕区域并识别文字",
                keywords: triggerWords,
                icon: icon
            )
        ]
    }

    public func perform(commandID: String) {
        guard commandID == "ocr.capture" || commandID == CommandID.openPlugin(Self.id) else { return }
        Task { await startCapture() }
    }

    // MARK: - QuickPlugin 协议

    public func makeView() -> AnyView {
        AnyView(OCRResultView(engine: engine))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
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
        deliver(text)
    }

    /// 把识别结果交付给用户：是否落到剪贴板由设置里的开关决定
    ///
    /// internal 而不是 private：接线测试要在既不跑 Vision、也不起 screencapture 的前提下
    /// 验证这个开关真的改变了行为，这是唯一能把它钉住的地方。
    func deliver(_ text: String) {
        guard !text.isEmpty else {
            EventBus.shared.post(ShowHUDEvent(message: "未识别到文字", tone: .info))
            return
        }

        // 开关在交付这一刻读：设置页改了立刻生效
        if OCRPreferences.autoCopy() {
            EventBus.shared.post(CopyToClipboardEvent(text: text))
            EventBus.shared.post(ShowHUDEvent(message: "识别完成，已复制到剪贴板", tone: .success))
        } else {
            // 关掉自动复制后不能再报「已复制到剪贴板」——那会是一句谎话；
            // 文字仍然在插件面板里，用户想复制还可以按那个按钮
            EventBus.shared.post(ShowHUDEvent(message: "识别完成", tone: .success))
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
                    let image = CGImage(
                        pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true,
                        intent: .defaultIntent)
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
