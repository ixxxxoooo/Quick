// ScreenCapture.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation
import QuickCore

/// 屏幕截图服务
///
/// 调用 macOS 系统截图工具进行屏幕捕获。去向、格式、是否带光标全部来自设置页，
/// 并且在每次截图时现读 —— 用户改完设置不需要重启应用。
@MainActor
@Observable
final class ScreenCapture {

    /// 最近一次截图路径
    ///
    /// 进剪贴板的截图没有文件，这时保持 nil —— 界面靠它判断该不该显示路径。
    private(set) var lastCapturePath: String?

    /// 是否正在截图中
    private(set) var isCapturing = false

    /// 截图保存目录
    private var saveDirectory: String {
        NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
    }

    // MARK: - 设置

    /// 设置页上的「保存到桌面」：关掉就只进剪贴板
    var savesToDesktop: Bool {
        Self.setting(PluginSettingKey.Screenshot.saveToDesktop, default: true)
    }

    /// 本次截图用的图片格式
    var format: CaptureFormat {
        CaptureFormat(settingValue: UserDefaults.standard.string(forKey: PluginSettingKey.Screenshot.format))
    }

    /// 设置页上的「包含鼠标指针」
    var includesPointer: Bool {
        Self.setting(PluginSettingKey.Screenshot.includePointer, default: false)
    }

    /// 读一个布尔设置
    ///
    /// 未设置过时取 `defaultValue`，它必须和设置页上那个开关的默认值一致 ——
    /// `bool(forKey:)` 直读会把「用户没动过」当成「用户关掉了」。
    private static func setting(_ key: String, default defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    // MARK: - 截图

    /// 区域截图
    /// - Returns: 是否成功
    func captureArea() async -> Bool {
        await capture(mode: .area)
    }

    /// 全屏截图
    /// - Returns: 是否成功
    func captureFullScreen() async -> Bool {
        await capture(mode: .fullScreen)
    }

    /// 窗口截图（使用 screencapture -w 交互式选择窗口，参考 jietu 的窗口截图）
    /// - Returns: 是否成功
    func captureWindow() async -> Bool {
        await capture(mode: .window)
    }

    /// 延时截图
    /// - Parameter delay: 延迟秒数
    /// - Returns: 是否成功
    func captureWithDelay(_ delay: Int) async -> Bool {
        await capture(mode: .delayed(seconds: delay))
    }

    // MARK: - 设置 → 命令行

    /// 把「当前设置 + 模式」翻译成一次截图请求
    ///
    /// 抽成函数是为了让「设置真的进了命令行」这件事能被断言 —— 起进程只发生在
    /// `runScreenCapture` 里，那一段在测试里没法跑。
    /// - Parameter mode: 截图模式
    /// - Returns: 截图请求
    func request(for mode: CaptureMode) -> CaptureRequest {
        let currentFormat = format
        let destination: CaptureDestination =
            savesToDesktop
            ? .file(
                path: ScreenshotCommand.outputPath(
                    in: saveDirectory, for: Date(), timeZone: .current, format: currentFormat))
            : .clipboard
        return CaptureRequest(
            mode: mode,
            destination: destination,
            format: currentFormat,
            includePointer: includesPointer)
    }

    // MARK: - 内部方法

    /// 按当前设置截一张图
    private func capture(mode: CaptureMode) async -> Bool {
        isCapturing = true
        defer { isCapturing = false }

        return await runScreenCapture(request(for: mode))
    }

    /// 执行 screencapture 命令
    private func runScreenCapture(_ request: CaptureRequest) async -> Bool {
        await withCheckedContinuation { continuation in
            let task = Process()
            task.launchPath = ScreenshotCommand.executablePath
            task.arguments = request.arguments

            task.terminationHandler = { [weak self] process in
                let success = process.terminationStatus == 0
                if success {
                    Task { @MainActor in
                        // 只有写文件的截图才有路径：以前从 arguments.last 取，进剪贴板时
                        // 会把 "-c" 当成路径记下来
                        self?.lastCapturePath = request.destination.filePath
                    }
                }
                continuation.resume(returning: success)
            }
            do {
                try task.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
