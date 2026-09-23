// PluginDefaults.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

extension PluginDefaults {

    /// 设置页语言选择器里的全部选项（与 `TranslationLanguages` 一致）
    public static var targetLanguageChoices: [String] { TranslationLanguages.all.map(\.code) }

    /// 设置页在「从未设置过」时显示的语言
    public static let defaultTargetLanguage = "zh-Hans"

    /// 目标语言
    ///
    /// 未设置过、或存了目录里没有的值（手改过偏好、老版本遗留）时回落到简体中文；
    /// 目录里确实提供的语言原样返回 —— 悄悄改写用户的选择会让「选了日语却出中文」
    /// 这件事披上合法的外壳。
    ///
    /// - Returns: 目标语言的 BCP-47 tag
    public static func targetLanguage() -> String {
        guard let stored = UserDefaults.standard.string(forKey: PluginSettingKey.Translator.targetLang),
            TranslationLanguages.option(for: stored) != nil
        else { return defaultTargetLanguage }
        return stored
    }
}
