// CalendarFormatting.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 日历相关文本格式化
enum CalendarFormatting {

    /// 农历日期文本
    ///
    /// 单独抽出来是因为它必须能在不启动 EventKit 的情况下被测试：
    /// 农历文本由「中国日历 + zh_CN」这组配置决定，配置被改动时输出会在界面上
    /// 悄悄变化，而不是编译报错。
    static func lunar(for date: Date) -> String {
        let chinese = Calendar(identifier: .chinese)
        let formatter = DateFormatter()
        formatter.calendar = chinese
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}
