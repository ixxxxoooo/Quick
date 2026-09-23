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
///   而设置页上的默认值可能是开的 —— 直读会把「用户没动过」当成「用户关掉了」。
enum PluginDefaults {

    /// 设置页语言选择器里的全部选项（与 `TranslationLanguages` 一致）
    static var targetLanguageChoices: [String] { TranslationLanguages.all.map(\.code) }

    /// 设置页在「从未设置过」时显示的语言
    static let defaultTargetLanguage = "zh-Hans"

    /// 目标语言
    ///
    /// 未设置过、或存了目录里没有的值（手改过偏好、老版本遗留）时回落到简体中文；
    /// 目录里确实提供的语言原样返回 —— 悄悄改写用户的选择会让「选了日语却出中文」
    /// 这件事披上合法的外壳。
    ///
    /// - Returns: 目标语言的 BCP-47 tag
    static func targetLanguage() -> String {
        guard let stored = UserDefaults.standard.string(forKey: PluginSettingKey.Translator.targetLang),
            TranslationLanguages.option(for: stored) != nil
        else { return defaultTargetLanguage }
        return stored
    }
}
