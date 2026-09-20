// ScreenshotCommand.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一次截图请求
enum CaptureMode: Sendable, Equatable {
    /// 交互式框选区域
    case area
    /// 整屏
    case fullScreen
    /// 延时若干秒后整屏
    case delayed(seconds: Int)
}

/// `screencapture` 的参数、文件名与输出路径的纯构造
///
/// 这些全是字符串拼接，和起进程、屏幕权限都无关，抽出来才能在不实际截图的前提下断言。
/// `ScreenCapture` 只剩「装配命令行并等它退出」这一件事。
enum ScreenshotCommand {

    /// 截图工具路径
    static let executablePath = "/usr/sbin/screencapture"

    /// 文件名前缀
    static let fileNamePrefix = "Quick_"

    /// 输出格式固定为 PNG
    static let fileExtension = "png"

    /// 时间戳格式：可排序、无分隔歧义的紧凑写法
    static let timestampFormat = "yyyyMMdd_HHmmss"

    /// 传给 `screencapture` 的参数列表
    ///
    /// 参数顺序不能改：`screencapture` 把最后一个位置参数当输出文件，
    /// 所以路径永远排在末尾，开关项排在它前面。
    /// - Parameters:
    ///   - mode: 截图模式
    ///   - outputPath: 输出文件的完整路径
    /// - Returns: 命令行参数
    static func arguments(mode: CaptureMode, outputPath: String) -> [String] {
        switch mode {
        case .area:
            // -i 交互式，-s 只允许框选（否则点一下会变成「点窗口」）
            ["-i", "-s", outputPath]
        case .fullScreen:
            [outputPath]
        case .delayed(let seconds):
            // -T 后跟秒数；秒数为 0 时也照样传，不做特判
            ["-T", "\(seconds)", outputPath]
        }
    }

    /// 时间戳（`yyyyMMdd_HHmmss`）
    ///
    /// 时区作为参数注入，测试才能用固定时区断言；调用方传 `.current`。
    static func timestamp(from date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = timestampFormat
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    /// 截图文件名
    static func fileName(for date: Date, timeZone: TimeZone) -> String {
        "\(fileNamePrefix)\(timestamp(from: date, timeZone: timeZone)).\(fileExtension)"
    }

    /// 输出文件的完整路径
    static func outputPath(in directory: String, for date: Date, timeZone: TimeZone) -> String {
        (directory as NSString).appendingPathComponent(fileName(for: date, timeZone: timeZone))
    }
}
