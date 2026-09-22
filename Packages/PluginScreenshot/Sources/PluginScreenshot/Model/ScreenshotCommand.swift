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
    /// 交互式窗口选择（参考 jietu 的窗口截图功能）
    case window
    /// 延时若干秒后整屏
    case delayed(seconds: Int)
}

/// 截图的去向
///
/// 设置页上的「保存到桌面」关掉之后截图不再落文件，而是直接进剪贴板 ——
/// 两种情况的命令行形态完全不同（带输出路径 vs `-c` 且没有位置参数），
/// 所以去向是参数构造的一部分，而不是一个「要不要加个开关」的布尔量。
enum CaptureDestination: Sendable, Equatable {
    /// 写到指定路径
    case file(path: String)
    /// 只进系统剪贴板
    case clipboard

    /// 会落盘的路径；进剪贴板时为 nil
    var filePath: String? {
        switch self {
        case .file(let path): path
        case .clipboard: nil
        }
    }
}

/// 图片编码格式
///
/// 设置页里存的字符串、`screencapture -t` 的参数、落盘扩展名这三件事必须一致，
/// 绑在一个类型里才不会出现「文件叫 .png、内容却是 HEIC」这种错配。
/// `rawValue` 是设置页存的值，`fileExtension` 既是落盘扩展名也是 `-t` 的参数
/// —— JPEG 上两者不同（`jpeg` / `jpg`），所以不能混用。
enum CaptureFormat: String, Sendable, CaseIterable {
    /// 无损，也是系统截图工具的默认格式
    case png
    /// 有损但紧凑
    case jpeg
    /// 同画质下体积最小
    case heic

    /// 落盘扩展名，同时也是 `-t` 的参数：`-t` 认的是 `jpeg` 的扩展名写法 `jpg`
    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }

    /// 从设置页存的值解析
    /// - Parameter settingValue: `screenshot.format` 里存的字符串
    init(settingValue: String?) {
        // 认不出来就当 PNG：设置值可能被手改过，为格式不符丢掉一整张截图不值得
        self = CaptureFormat(rawValue: settingValue ?? "") ?? .png
    }
}

/// 一次截图请求：模式 + 去向 + 格式 + 是否带上光标
///
/// 设置页上的开关最终都落在这几个字段上，命令行由它们拼出来。
struct CaptureRequest: Sendable, Equatable {
    let mode: CaptureMode
    let destination: CaptureDestination
    let format: CaptureFormat
    let includePointer: Bool

    /// 传给 `screencapture` 的参数
    var arguments: [String] {
        ScreenshotCommand.arguments(
            mode: mode, destination: destination, format: format, includePointer: includePointer)
    }
}

/// `screencapture` 的参数、文件名与输出路径的纯构造
///
/// 这些全是字符串拼接，和起进程、屏幕权限都无关，抽出来才能在不实际截图的前提下断言。
/// `ScreenCapture` 只剩「按当前设置拼一次请求并等它退出」这一件事。
enum ScreenshotCommand {

    /// 截图工具路径
    static let executablePath = "/usr/sbin/screencapture"

    /// 文件名前缀
    static let fileNamePrefix = "Quick_"

    /// 时间戳格式：可排序、无分隔歧义的紧凑写法
    static let timestampFormat = "yyyyMMdd_HHmmss"

    /// 传给 `screencapture` 的参数列表
    ///
    /// 参数顺序不能改：`screencapture` 把最后一个位置参数当输出文件，
    /// 所以路径永远排在末尾，开关项排在它前面。
    /// - Parameters:
    ///   - mode: 截图模式
    ///   - destination: 存成文件还是进剪贴板
    ///   - format: 图片格式，只在存成文件时进命令行
    ///   - includePointer: 是否把鼠标光标一起截进去
    /// - Returns: 命令行参数
    static func arguments(
        mode: CaptureMode,
        destination: CaptureDestination,
        format: CaptureFormat,
        includePointer: Bool
    ) -> [String] {
        var arguments: [String] = []

        switch mode {
        case .area:
            // -i 交互式，-s 只允许框选（否则点一下会变成「点窗口」）
            arguments += ["-i", "-s"]
        case .fullScreen:
            break
        case .window:
            // -W：交互式从「点窗口」开始（参考 jietu 窗口截图），比单靠 -w 更稳
            arguments += ["-i", "-W"]
        case .delayed(let seconds):
            // -T 后跟秒数；秒数为 0 时也照样传，不做特判
            arguments += ["-T", "\(seconds)"]
        }

        if includePointer {
            // -C 就是「连光标一起截」。man 页说它只在非交互模式下允许，但按模式特判
            // 只会让这个开关在区域截图上静默失效
            arguments.append("-C")
        }

        switch destination {
        case .file(let path):
            // -t 收的是扩展名写法（man 页举的 pdf / jpg / tiff 都是扩展名），所以用
            // fileExtension 而不是设置里存的那个值 —— 两者在 JPEG 上并不相同
            arguments += ["-t", format.fileExtension, path]
        case .clipboard:
            // -c 且不给输出路径：画面直接进剪贴板，不落文件。这种模式下 -t 没有意义
            // （进剪贴板的是像素，不经过编码器），所以不传
            arguments.append("-c")
        }

        return arguments
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
    static func fileName(for date: Date, timeZone: TimeZone, format: CaptureFormat) -> String {
        "\(fileNamePrefix)\(timestamp(from: date, timeZone: timeZone)).\(format.fileExtension)"
    }

    /// 输出文件的完整路径
    static func outputPath(
        in directory: String, for date: Date, timeZone: TimeZone, format: CaptureFormat
    ) -> String {
        let name = fileName(for: date, timeZone: timeZone, format: format)
        return (directory as NSString).appendingPathComponent(name)
    }
}
