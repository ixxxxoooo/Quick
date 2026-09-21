// OCRSettingsTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginOCR

// MARK: - 纯映射

@Suite("OCR 语言档位映射")
struct OCRLanguageTests {

    @Test("档位列表非空且自动检测在第一位")
    func choicesAreWellFormed() {
        #expect(OCRLanguage.choices.first == OCRLanguage.automatic)
        #expect(OCRLanguage.choices.allSatisfy { !$0.isEmpty })
        #expect(Set(OCRLanguage.choices).count == OCRLanguage.choices.count)
    }

    @Test("自动检测：交给 Vision 自己判定，不写死候选语言")
    func automaticLeavesTheLanguagesToVision() {
        let settings = OCRLanguage.settings(for: OCRLanguage.automatic)

        #expect(settings.detectsLanguageAutomatically)
        #expect(settings.recognitionLanguages.isEmpty)
    }

    @Test("手改坏的值与旧值都退回自动检测")
    func unknownValuesFallBackToAutomatic() {
        for value in ["", "zh", "klingon", "zh-Hans-CN", "AUTO"] {
            #expect(OCRLanguage.normalized(value) == OCRLanguage.automatic, "\(value) 应退回自动检测")
            #expect(
                OCRLanguage.settings(for: value)
                    == OCRLanguage.settings(for: OCRLanguage.automatic)
            )
        }
        #expect(OCRLanguage.normalized("ja") == "ja")
        #expect(OCRLanguage.normalized("zh-Hans") == "zh-Hans")
    }

    @Test("指定语言：关掉自动检测，选中的语言排在候选表第一位")
    func explicitChoiceLeadsTheCandidateList() {
        let chinese = OCRLanguage.settings(for: "zh-Hans")
        let english = OCRLanguage.settings(for: "en")
        let japanese = OCRLanguage.settings(for: "ja")

        #expect(!chinese.detectsLanguageAutomatically)
        #expect(chinese.recognitionLanguages.first == Locale.Language(identifier: "zh-Hans"))
        #expect(english.recognitionLanguages.first == Locale.Language(identifier: "en-US"))
        #expect(japanese.recognitionLanguages.first == Locale.Language(identifier: "ja"))

        // 三个档位互不相同，也不是同一份列表换了个顺序
        #expect(chinese.recognitionLanguages != english.recognitionLanguages)
        #expect(english.recognitionLanguages != japanese.recognitionLanguages)
    }

    @Test("选中的语言不再在候选表里重复出现，其余兜底语言一个不少")
    func candidateListKeepsFallbacksWithoutDuplicates() {
        let english = OCRLanguage.settings(for: "en")

        #expect(english.recognitionLanguages.count == OCRLanguage.fallbackLanguages.count)
        #expect(Set(english.recognitionLanguages).count == english.recognitionLanguages.count)
        #expect(english.recognitionLanguages.contains(Locale.Language(identifier: "zh-Hans")))
        #expect(english.recognitionLanguages.contains(Locale.Language(identifier: "ja")))
        // en 展开成 en-US 之后，兜底表里的 en-US 不能再出现一次
        #expect(english.recognitionLanguages.filter { $0 == Locale.Language(identifier: "en-US") }.count == 1)
    }
}

// MARK: - 偏好读取

@Suite("OCR 偏好读取")
struct OCRPreferencesTests {

    /// 独立 suite：读映射的用例不碰真实偏好
    private static func scratchDefaults() -> UserDefaults? {
        UserDefaults(suiteName: "com.ygw.quick.tests.ocr.\(UUID().uuidString)")
    }

    @Test("未设置过时就是设置页显示的档位：自动检测 + 自动复制")
    func emptyDefaultsFallBackToThePaneDefaults() throws {
        let defaults = try #require(Self.scratchDefaults())

        #expect(OCRPreferences.language(defaults: defaults) == OCRLanguage.automatic)
        #expect(OCRPreferences.autoCopy(defaults: defaults))
    }

    @Test("语言档位跟着键走")
    func languageFollowsTheStoredValue() throws {
        let defaults = try #require(Self.scratchDefaults())

        for choice in OCRLanguage.choices {
            defaults.set(choice, forKey: PluginSettingKey.OCR.language)
            #expect(OCRPreferences.language(defaults: defaults) == choice)
        }

        defaults.set("nonsense", forKey: PluginSettingKey.OCR.language)
        #expect(OCRPreferences.language(defaults: defaults) == OCRLanguage.automatic)
    }

    @Test("自动复制跟着开关走")
    func autoCopyFollowsTheToggle() throws {
        let defaults = try #require(Self.scratchDefaults())

        defaults.set(false, forKey: PluginSettingKey.OCR.autoCopy)
        #expect(!OCRPreferences.autoCopy(defaults: defaults))
        defaults.set(true, forKey: PluginSettingKey.OCR.autoCopy)
        #expect(OCRPreferences.autoCopy(defaults: defaults))
    }
}

// MARK: - 引擎与插件的接线

@Suite("OCR 引擎与会话的接线")
struct OCREngineSettingsTests {

    @Test("引擎把设置里的语言档位翻译成 Vision 参数")
    @MainActor
    func enginePassesTheConfiguredLanguageThrough() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "com.ygw.quick.tests.ocr.\(UUID().uuidString)"))
        let engine = OCREngine(defaults: defaults)

        #expect(engine.configuredLanguageSettings.detectsLanguageAutomatically)

        defaults.set("ja", forKey: PluginSettingKey.OCR.language)
        #expect(
            engine.configuredLanguageSettings.recognitionLanguages.first == Locale.Language(identifier: "ja"))
        #expect(!engine.configuredLanguageSettings.detectsLanguageAutomatically)

        defaults.set("zh-Hans", forKey: PluginSettingKey.OCR.language)
        #expect(
            engine.configuredLanguageSettings.recognitionLanguages.first
                == Locale.Language(identifier: "zh-Hans"))
    }
}

/// 插件交付结果时读的是标准偏好存储，用例也只能写标准存储 —— 换成独立 suite 就测不到接线了。
/// 标准存储是进程共享的，所以用例串行并自己收尾。
@MainActor
@Suite("OCR 插件的设置接线", .serialized)
struct OCRPluginSettingsTests {

    private static let autoCopyKey = PluginSettingKey.OCR.autoCopy

    /// 跑完把旧值原样放回去，不让用例互相污染，也不留在真实偏好里
    private static func withStandardDefaults(_ body: () async throws -> Void) async throws {
        let previous = UserDefaults.standard.object(forKey: autoCopyKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: autoCopyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: autoCopyKey)
            }
        }
        try await body()
    }

    @Test("识别完成后是否落剪贴板由开关决定")
    func autoCopyDecidesWhetherTheResultIsCopied() async throws {
        try await Self.withStandardDefaults {
            var copied: [String] = []
            let subscription = EventBus.shared.on(CopyToClipboardEvent.self) { copied.append($0.text) }
            defer { subscription.cancel() }

            let plugin = OCRPlugin()

            UserDefaults.standard.set(true, forKey: Self.autoCopyKey)
            plugin.deliver("第一行\nsecond")
            #expect(copied == ["第一行\nsecond"])

            // 关掉之后不能再往剪贴板里写东西
            UserDefaults.standard.set(false, forKey: Self.autoCopyKey)
            plugin.deliver("第一行\nsecond")
            #expect(copied == ["第一行\nsecond"])
        }
    }

    @Test("没识别到文字时不复制、也不报成功")
    func emptyResultIsNotCopied() async throws {
        try await Self.withStandardDefaults {
            var copied: [String] = []
            let subscription = EventBus.shared.on(CopyToClipboardEvent.self) { copied.append($0.text) }
            defer { subscription.cancel() }

            UserDefaults.standard.set(true, forKey: Self.autoCopyKey)
            OCRPlugin().deliver("")

            #expect(copied.isEmpty)
        }
    }
}
