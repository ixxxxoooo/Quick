// CalendarPreferences.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 日历插件的偏好读取
///
/// 每次现读：设置页可以在运行期改。默认值与设置页上控件的默认值一致。
enum CalendarPreferences {

    static let defaultReminderMinutes = 10

    /// 提前多少分钟提醒；0 或负数表示关闭
    static func reminderMinutes(defaults: UserDefaults = .standard) -> Int {
        let value = defaults.object(forKey: PluginSettingKey.Calendar.reminderMinutes) as? Int
            ?? defaultReminderMinutes
        return min(max(value, 0), 24 * 60)
    }

    /// 是否识别会议链接并显示「加入会议」
    static func extractsMeetingLinks(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: PluginSettingKey.Calendar.autoExtractMeetingLinks) as? Bool ?? true
    }

    /// 月历是否显示周数列
    static func showsWeekNumber(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: PluginSettingKey.Calendar.showWeekNumber) as? Bool ?? false
    }
}
