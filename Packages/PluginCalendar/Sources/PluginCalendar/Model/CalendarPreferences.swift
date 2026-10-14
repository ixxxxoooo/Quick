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

    /// 上次使用的视图；缺失或非法回落月视图
    static func viewMode(defaults: UserDefaults = .standard) -> CalendarViewMode {
        CalendarViewMode(storedValue: defaults.string(forKey: PluginSettingKey.Calendar.viewMode))
    }

    /// 是否显示法定节假日
    static func showsHolidays(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: PluginSettingKey.Calendar.showHolidays) as? Bool ?? true
    }

    /// 是否显示黄历（干支、生肖、节气、节日）
    static func showsAlmanac(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: PluginSettingKey.Calendar.showAlmanac) as? Bool ?? true
    }

    /// 是否联网更新节假日数据
    static func updatesHolidaysOnline(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: PluginSettingKey.Calendar.updateHolidaysOnline) as? Bool ?? true
    }
}
