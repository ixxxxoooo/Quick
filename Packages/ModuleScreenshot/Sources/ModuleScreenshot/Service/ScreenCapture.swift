// ScreenCapture.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation

/// 屏幕截图服务
///
/// 调用 macOS 系统截图工具进行屏幕捕获。
@MainActor
@Observable
final class ScreenCapture {

    /// 最近一次截图路径
    private(set) var lastCapturePath: String?

    /// 是否正在截图中
    private(set) var isCapturing = false

    /// 截图保存目录
    private var saveDirectory: String {
        NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
    }

    /// 区域截图
    /// - Returns: 是否成功
    func captureArea() async -> Bool {
        isCapturing = true
        defer { isCapturing = false }

        let filename = "Quick_\(timestamp()).png"
        let path = (saveDirectory as NSString).appendingPathComponent(filename)

        return await runScreenCapture(arguments: ["-i", "-s", path])
    }

    /// 全屏截图
    /// - Returns: 是否成功
    func captureFullScreen() async -> Bool {
        isCapturing = true
        defer { isCapturing = false }

        let filename = "Quick_\(timestamp()).png"
        let path = (saveDirectory as NSString).appendingPathComponent(filename)

        return await runScreenCapture(arguments: [path])
    }

    /// 延时截图
    /// - Parameter delay: 延迟秒数
    /// - Returns: 是否成功
    func captureWithDelay(_ delay: Int) async -> Bool {
        isCapturing = true
        defer { isCapturing = false }

        let filename = "Quick_\(timestamp()).png"
        let path = (saveDirectory as NSString).appendingPathComponent(filename)

        return await runScreenCapture(arguments: ["-T", "\(delay)", path])
    }

    // MARK: - 内部方法

    /// 执行 screencapture 命令
    private func runScreenCapture(arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            task.arguments = arguments

            task.terminationHandler = { [weak self] process in
                let success = process.terminationStatus == 0
                if success, let path = arguments.last {
                    Task { @MainActor in
                        self?.lastCapturePath = path
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

    /// 时间戳文件名
    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
