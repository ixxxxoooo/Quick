// PluginDefaults.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 片段插件读偏好的入口
///
/// 单独一层是为了把两件事固定下来：
/// - **每次用的时候现读，不缓存。** 设置页可以在运行期改，缓存下来的值会和
///   `UserDefaults` 漂移，表现就是「设置改了没反应」。
/// - **默认值必须显式给出。** `bool(forKey:)` 对没写过的键返回 `false`，
///   而设置页上的开关默认是开的 —— 直读会把「用户没动过」当成「用户关掉了」。
enum PluginDefaults {

    /// 读一个布尔设置
    /// - Parameters:
    ///   - key: `PluginSettingKey` 里的键
    ///   - defaultValue: 用户从未设置过时的取值，必须与设置页上那个开关的默认值一致
    /// - Returns: 设置值
    static func isEnabled(_ key: String, default defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}
