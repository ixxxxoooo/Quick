// TemplateEngine.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation

/// 模板引擎
///
/// 支持在文本片段中使用变量，展开时替换为实际值。
/// 内置变量：{date}, {time}, {datetime}, {clipboard}, {random}
@MainActor
final class TemplateEngine {

    /// 展开模板变量
    /// - Parameter template: 含变量的模板字符串
    /// - Returns: 替换变量后的最终文本
    func expand(_ template: String) -> String {
        var result = template

        let now = Date()
        let dateFormatter = DateFormatter()

        // {date} → 当前日期
        dateFormatter.dateFormat = "yyyy-MM-dd"
        result = result.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: now))

        // {time} → 当前时间
        dateFormatter.dateFormat = "HH:mm:ss"
        result = result.replacingOccurrences(of: "{time}", with: dateFormatter.string(from: now))

        // {datetime} → 完整日期时间
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        result = result.replacingOccurrences(of: "{datetime}", with: dateFormatter.string(from: now))

        // {clipboard} → 当前剪贴板内容
        if result.contains("{clipboard}") {
            let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
            result = result.replacingOccurrences(of: "{clipboard}", with: clipboard)
        }

        // {random} → 随机 UUID
        result = result.replacingOccurrences(of: "{random}", with: UUID().uuidString)

        // {timestamp} → Unix 时间戳
        result = result.replacingOccurrences(of: "{timestamp}", with: "\(Int(now.timeIntervalSince1970))")

        return result
    }
}
