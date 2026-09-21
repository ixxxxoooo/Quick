// PluginDefaults.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 翻译插件读偏好的入口
///
/// 单独一层是为了把两件事固定下来：
/// - **每次用的时候现读，不缓存。** 设置页可以在运行期改，缓存下来的值会和
///   `UserDefaults` 漂移，表现就是「设置改了没反应」。
/// - **默认值必须显式给出。** `bool(forKey:)` 对没写过的键返回 `false`，
///   而设置页上的开关默认是开的 —— 直读会把「用户没动过」当成「用户关掉了」。
enum PluginDefaults {

    /// 设置页语言选择器里的全部选项（与 Picker 的 tag 一一对应）
    static let targetLanguageChoices = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de"]

    /// 设置页在「从未设置过」时显示的语言
    static let defaultTargetLanguage = "zh-Hans"

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

    /// 目标语言
    ///
    /// 未设置过时按设置页显示的简体中文处理。存了设置页里没有的值（手改过偏好文件、
    /// 老版本的遗留值）也回落到同一个默认；但设置页里确实提供的七种语言**原样返回** ——
    /// 把日语这类词表表达不了的语言改写成中文，会让「选了日语却出中文」这件事
    /// 披上合法的外壳，宁可让下游看到真实的选择。
    ///
    /// - Returns: 目标语言的 BCP-47 tag
    static func targetLanguage() -> String {
        guard let stored = UserDefaults.standard.string(forKey: PluginSettingKey.Translator.targetLang),
            targetLanguageChoices.contains(stored)
        else { return defaultTargetLanguage }
        return stored
    }
}
