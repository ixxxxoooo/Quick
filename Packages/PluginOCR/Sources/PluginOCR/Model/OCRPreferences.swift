// OCRPreferences.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// Vision 请求里与识别语言有关的两项设置
///
/// 单独成一个类型，是为了让「设置页的档位 → 请求参数」这一步在没有 Vision 的地方也能被断言。
struct OCRLanguageSettings: Equatable, Sendable {

    /// 让 Vision 自己判断文字用的是哪种文字体系（对应 `RecognizeTextRequest.automaticallyDetectsLanguage`）
    let detectsLanguageAutomatically: Bool

    /// 显式写给 Vision 的语言候选，顺序即优先级。
    /// 为空表示不写这一项，交给 Vision 自己的默认档。
    let recognitionLanguages: [Locale.Language]
}

/// OCR 的语言档位映射
///
/// 设置页只有四个档位（自动 / 简体中文 / 英语 / 日语），这里负责把它们翻译成 Vision 能用的参数。
/// 纯映射，所以能脱离 Vision 固定住结果。
enum OCRLanguage {

    /// 「自动检测」的存储值
    static let automatic = "auto"

    /// 设置页里可选的档位
    static let choices = [automatic, "zh-Hans", "en", "ja"]

    /// 挑中一门语言之后跟在它后面的兜底候选
    ///
    /// 设置页承诺的是「**优先**识别的文字语言」，不是「只认这门语言」，所以选中的语言排第一，
    /// 其余按这个顺序跟在后面 —— 选了英语之后中文截图仍要认得出来。
    static let fallbackLanguages = [
        Locale.Language(identifier: "zh-Hans"),
        Locale.Language(identifier: "zh-Hant"),
        Locale.Language(identifier: "en-US"),
        Locale.Language(identifier: "ja"),
        Locale.Language(identifier: "ko")
    ]

    /// 把存储值规范化成设置页里的档位
    ///
    /// 手改过的偏好、旧版本留下的值都可能不在 `choices` 里，一律当作自动检测 ——
    /// 那是最不可能出错的一档。
    static func normalized(_ storedValue: String) -> String {
        choices.contains(storedValue) ? storedValue : automatic
    }

    /// 存储值 → Vision 请求的语言设置
    static func settings(for storedValue: String) -> OCRLanguageSettings {
        guard let preferred = preferredLanguage(for: normalized(storedValue)) else {
            // 自动检测：一门语言都不写死，让 Vision 按画面自行判定
            return OCRLanguageSettings(
                detectsLanguageAutomatically: true,
                recognitionLanguages: []
            )
        }

        return OCRLanguageSettings(
            detectsLanguageAutomatically: false,
            recognitionLanguages: [preferred] + fallbackLanguages.filter { $0 != preferred }
        )
    }

    /// 设置页里的语言档位 → 具体语言标识
    ///
    /// `en` 展开成 `en-US`：Vision 的候选表里是带地区的标识符。
    private static func preferredLanguage(for choice: String) -> Locale.Language? {
        switch choice {
        case "zh-Hans":
            Locale.Language(identifier: "zh-Hans")
        case "en":
            Locale.Language(identifier: "en-US")
        case "ja":
            Locale.Language(identifier: "ja")
        default:
            nil
        }
    }
}

/// OCR 偏好的读取
///
/// 读键的动作发生在**每次识别**与**每次交付结果**时，不是在插件 init 里读一次：
/// 设置页可以在应用运行期间随时改。
enum OCRPreferences {

    /// 当前的语言档位
    static func language(defaults: UserDefaults = .standard) -> String {
        OCRLanguage.normalized(
            defaults.string(forKey: PluginSettingKey.OCR.language) ?? OCRLanguage.automatic)
    }

    /// 识别完成后是否自动复制到剪贴板
    static func autoCopy(defaults: UserDefaults = .standard) -> Bool {
        // 没写过这个键时要按设置页显示的「开」处理，不能直接用 bool(forKey:)（它把未设置读成 false）
        guard defaults.object(forKey: PluginSettingKey.OCR.autoCopy) != nil else { return true }
        return defaults.bool(forKey: PluginSettingKey.OCR.autoCopy)
    }
}
