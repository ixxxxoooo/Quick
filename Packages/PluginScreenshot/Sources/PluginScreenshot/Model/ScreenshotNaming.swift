// ScreenshotNaming.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 图片编码格式
///
/// 设置页里存的字符串、落盘扩展名这两件事必须一致，绑在一个类型里才不会出现
/// 「文件叫 .png、内容却是 HEIC」这种错配。`rawValue` 是设置页存的值。
enum CaptureFormat: String, Sendable, CaseIterable {
    /// 无损
    case png
    /// 有损但紧凑
    case jpeg
    /// 同画质下体积最小
    case heic

    /// 落盘扩展名
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

/// 截图文件名的纯构造
///
/// 全是字符串拼接，与实际抓屏无关，抽出来才能脱离屏幕权限断言。
enum ScreenshotNaming {

    /// 文件名前缀
    static let fileNamePrefix = "Quick_"

    /// 时间戳格式：可排序、无分隔歧义的紧凑写法
    static let timestampFormat = "yyyyMMdd_HHmmss"

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
