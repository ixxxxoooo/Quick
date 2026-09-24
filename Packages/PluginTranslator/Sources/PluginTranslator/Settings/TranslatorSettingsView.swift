// TranslatorSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct TranslatorSettingsView: View {
    @AppStorage(PluginSettingKey.Translator.targetLang) private var targetLang = "zh-Hans"

    /// 与插件里的 `TranslationLanguages.all` 保持一致（QuickUI 不认识插件，只能并列一份）
    private static let languages: [(code: String, label: String)] = [
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁体中文"),
        ("en", "英语"),
        ("ja", "日语"),
        ("ko", "韩语"),
        ("fr", "法语"),
        ("de", "德语"),
        ("es", "西班牙语"),
        ("ru", "俄语"),
        ("it", "意大利语"),
        ("pt", "葡萄牙语"),
        ("ar", "阿拉伯语"),
        ("th", "泰语"),
        ("vi", "越南语")
    ]

    var body: some View {
        Section {
            Picker(selection: $targetLang) {
                ForEach(Self.languages, id: \.code) { language in
                    Text(language.label).tag(language.code)
                }
            } label: {
                SettingsRow(
                    title: "默认目标语言",
                    subtitle: "翻译结果默认输出的语言。源语言在插件面板里切换，默认自动识别。",
                    icon: { SettingsRowIcon(systemImage: "globe") }
                )
            }
        } header: {
            Text("语言偏好")
        } footer: {
            Text(
                "在面板里输入「翻译 <文本>」或「translate <文本>」翻译；输入「词典 <单词>」或「dict <单词>」查词。翻译在端上完成，不联网。"
            )
        }
    }
}

/// JSON 格式化的专属选项
///
/// 键与 `JSONFormatterView` 里的 `@AppStorage` 是同一个 —— 这里改的就是工具面板里那一项，
/// 两边读写同一份值，不存在「设置里能调但工具不理会」的假开关。
