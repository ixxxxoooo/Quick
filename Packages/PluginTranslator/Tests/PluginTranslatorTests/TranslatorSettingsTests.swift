// TranslatorSettingsTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginTranslator

// MARK: - 目标语言映射（纯逻辑）

@Suite("目标语言到方向的映射")
struct TargetLanguageMappingTests {

    @Test("词表能服务的中文两种写法都映射到译成中文")
    func chineseTargetsMapToChinese() {
        #expect(TranslationDirection.target(forLanguageCode: "zh-Hans") == .toChinese)
        #expect(TranslationDirection.target(forLanguageCode: "zh-Hant") == .toChinese)
    }

    @Test("英语映射到译成英文")
    func englishMapsToEnglish() {
        #expect(TranslationDirection.target(forLanguageCode: "en") == .toEnglish)
    }

    @Test("词表服务不了的语言不映射成任何方向")
    func unservedLanguagesHaveNoDirection() {
        // 设置页里能选这四个，但词表里只有中英两向。宁可返回 nil 让它退回按源语言判定，
        // 也不能假装成中文或英文方向 —— 那会把结果标成一种它并没有译成的语言
        for code in ["ja", "ko", "fr", "de"] {
            #expect(
                TranslationDirection.target(forLanguageCode: code) == nil,
                "\(code) 没有词表支撑，不该被映射成方向")
        }
        #expect(TranslationDirection.target(forLanguageCode: nil) == nil)
        #expect(TranslationDirection.target(forLanguageCode: "") == nil)
        #expect(TranslationDirection.target(forLanguageCode: "zh") == nil)
    }
}

@Suite("方向取舍")
struct DirectionResolutionTests {

    @Test("配置的目标语言压过识别出来的源语言")
    func configuredTargetBeatsDetection() {
        // 识别到中文，但用户要的是中文 —— 不该自作主张译成英文
        #expect(
            TranslationDirection.direction(
                sourceLanguage: "zh-Hans", targetLanguage: "zh-Hans", autoDetect: true)
                == .toChinese)
        // 识别到中文，用户要英文
        #expect(
            TranslationDirection.direction(
                sourceLanguage: "zh-Hans", targetLanguage: "en", autoDetect: true)
                == .toEnglish)
        // 识别到英文，用户仍要英文
        #expect(
            TranslationDirection.direction(
                sourceLanguage: "en", targetLanguage: "en", autoDetect: true) == .toEnglish)
    }

    @Test("关掉自动检测后，方向不再参考源语言")
    func autoDetectOffIgnoresTheSourceLanguage() {
        // 同一份源语言，开关两态给出不同方向 —— 这正是开关要能观察到的差异
        let detected = "zh-Hans"
        #expect(
            TranslationDirection.direction(
                sourceLanguage: detected, targetLanguage: nil, autoDetect: true) == .toEnglish)
        #expect(
            TranslationDirection.direction(
                sourceLanguage: detected, targetLanguage: nil, autoDetect: false) == .toChinese)
        // 目标语言能表达时，两态一致：目标语言本来就是方向的决定者
        #expect(
            TranslationDirection.direction(
                sourceLanguage: detected, targetLanguage: "en", autoDetect: false) == .toEnglish)
    }

    @Test("目标语言表达不了时退回按源语言判定")
    func unservedTargetFallsBackToDetection() {
        #expect(
            TranslationDirection.direction(
                sourceLanguage: "zh-Hans", targetLanguage: "ja", autoDetect: true) == .toEnglish)
        #expect(
            TranslationDirection.direction(
                sourceLanguage: "en", targetLanguage: "fr", autoDetect: true) == .toChinese)
    }

    @Test("设置页列出的七种语言都有名字，默认是简体中文")
    func paneChoicesAreDeclared() {
        #expect(PluginDefaults.targetLanguageChoices == ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de"])
        #expect(PluginDefaults.defaultTargetLanguage == "zh-Hans")
    }
}

// MARK: - 插件接线

/// 这一组验证设置页上的两个开关真的改变了行为，而不是只把值写进 `UserDefaults`。
///
/// 服务读的是标准偏好存储，用例也只能写标准存储 —— 换成独立 suite 就测不到接线了。
/// 标准存储是进程共享的，所以用例必须串行并自己收尾（见 `withStandardDefaults`）。
@Suite("翻译插件的设置接线", .serialized)
@MainActor
struct TranslatorSettingWiringTests {

    private static let touchedKeys = [
        PluginSettingKey.Translator.targetLang,
        PluginSettingKey.Translator.autoDetect
    ]

    /// 跑完把这两个键的旧值原样放回去，不让用例互相污染，也不留在真实偏好里
    private static func withStandardDefaults(_ body: () async throws -> Void) async throws {
        var saved: [String: Any] = [:]
        for key in touchedKeys {
            saved[key] = UserDefaults.standard.object(forKey: key)
        }
        defer {
            for key in touchedKeys {
                if let previous = saved[key] {
                    UserDefaults.standard.set(previous, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        try await body()
    }

    /// 词表外的词只留下兜底文案，目标语言就写在文案里 —— 方向因此可以被观察到
    private static let unknownWord = "苹果"

    @Test("目标语言决定兜底文案里标注的语言")
    func targetLanguageReachesTheResult() async throws {
        try await Self.withStandardDefaults {
            let service = TranslationService()

            UserDefaults.standard.set("en", forKey: PluginSettingKey.Translator.targetLang)
            #expect(await service.translate(Self.unknownWord) == "[英文翻译] 苹果")

            UserDefaults.standard.set("zh-Hans", forKey: PluginSettingKey.Translator.targetLang)
            #expect(await service.translate(Self.unknownWord) == "[中文翻译] 苹果")
        }
    }

    @Test("没设置过时按设置页显示的简体中文，手改坏的值同样回落")
    func unsetTargetUsesThePaneDefault() async throws {
        try await Self.withStandardDefaults {
            UserDefaults.standard.removeObject(forKey: PluginSettingKey.Translator.targetLang)
            #expect(await TranslationService().translate(Self.unknownWord) == "[中文翻译] 苹果")

            UserDefaults.standard.set("xx-YY", forKey: PluginSettingKey.Translator.targetLang)
            #expect(
                await TranslationService().translate(Self.unknownWord) == "[中文翻译] 苹果",
                "不是设置页提供的语言 tag 时应当回落到默认，而不是当成某种方向")
        }
    }

    @Test("设置页里的语言原样生效：选了词表服务不了的语言不会被改成中文")
    func unservedTargetIsNotRewritten() async throws {
        try await Self.withStandardDefaults {
            UserDefaults.standard.set("ja", forKey: PluginSettingKey.Translator.targetLang)
            UserDefaults.standard.set(true, forKey: PluginSettingKey.Translator.autoDetect)

            // 目标是日语，词表表达不了，于是方向仍由识别出的中文决定 —— 译成英文。
            // 如果读取时把日语悄悄改成简体中文，这里会变成「[中文翻译] 苹果」
            #expect(await TranslationService().translate(Self.unknownWord) == "[英文翻译] 苹果")
        }
    }

    @Test("自动检测开关：关掉后不再识别语言，方向只由目标语言决定")
    func autoDetectControlsTheRecognizer() async throws {
        try await Self.withStandardDefaults {
            // 目标是词表表达不了的语言，方向就完全取决于「有没有做识别」，
            // 于是开关的两态会给出两种不同的译文
            UserDefaults.standard.set("ja", forKey: PluginSettingKey.Translator.targetLang)
            let chinese = "今天天气很好，我们一起去公园散步吧。"

            UserDefaults.standard.set(true, forKey: PluginSettingKey.Translator.autoDetect)
            let detecting = TranslationService()
            let withDetection = await detecting.translate(chinese)
            #expect(detecting.detectedLanguage != nil, "开着自动检测却没有识别出源语言")
            #expect(withDetection == "[英文翻译] \(chinese)")

            UserDefaults.standard.set(false, forKey: PluginSettingKey.Translator.autoDetect)
            let blind = TranslationService()
            let withoutDetection = await blind.translate(chinese)
            #expect(blind.detectedLanguage == nil, "关掉自动检测后不该再识别语言")
            #expect(withoutDetection == "[中文翻译] \(chinese)")
        }
    }
}
