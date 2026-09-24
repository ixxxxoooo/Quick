// TranslatorPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 翻译插件
///
/// 端上翻译（Apple `Translation` 框架）+ 系统词典（`DictionaryServices`）+ 系统朗读
/// （`AVSpeechSynthesizer`），全部离线、零第三方依赖。主面板里输入 `翻译 …` / `词典 …`
/// 直接给结果，打开插件面板则是完整的输入 / 译文 / 词典三卡片工作台。
@MainActor
public final class TranslatorPlugin: QuickPlugin, PluginViewProviding {

    public static let id = "translator"
    public static let name = "翻译"
    public static let icon = "character.book.closed.fill"
    public static let description =
        "端上翻译与系统词典：自动识别语言、中英日韩等多语互译，单词给音标与释义，支持朗读与历史记录。"
    public static let triggerWords = ["翻译", "translate", "translation", "词典", "dict", "dictionary"]

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "translator.translate", pluginID: id, pluginName: name, title: "翻译文本",
                subtitle: "端上翻译一段文本", keywords: ["翻译", "tr", "translate"],
                icon: "character.book.closed"),
            CommandDescriptor(
                id: "translator.dict", pluginID: id, pluginName: name, title: "查词",
                subtitle: "查单词的音标与释义", keywords: ["词典", "dict", "dictionary"],
                icon: "text.book.closed")
        ]
    }

    public var isEnabled = true

    private let log = QuickLog.plugin(TranslatorPlugin.id)

    /// 翻译服务
    let service = TranslationService()
    /// 系统词典
    let dictionary = DictionaryService()
    /// 朗读
    let speech = SpeechService()
    /// 历史
    let history: TranslationHistoryStore

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public init(storage: PluginStorage) {
        history = TranslationHistoryStore(storage: storage)
    }

    // MARK: - QuickPlugin 协议

    public func accepts(query: String) -> Bool {
        TranslatorQuery.intent(in: query) != nil
    }

    public nonisolated func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }

        guard let intent = TranslatorQuery.intent(in: query) else { return [] }
        switch intent {
        case .dictionary(let word):
            // 词典走 DictionaryServices，它拿的是非 Sendable 的 CFRange 结果，
            // 服务因此是主 actor 的；显式跳回去，这次跳转是有意的。
            return await dictionaryItems(for: word)
        case .translate(let text):
            return await translationItems(for: text)
        }
    }

    /// 单词：词典条目一条
    ///
    /// `@MainActor`：`DictionaryService` 包着非 Sendable 的系统 API，
    /// 结果取回后立刻映射成 `Sendable` 的条目，后续处理不再需要主 actor。
    private func dictionaryItems(for word: String) async -> [SearchableItem] {
        guard let entry = dictionary.lookup(word), !entry.isEmpty else { return [] }
        return Self.dictionaryItem(for: entry, word: word)
    }

    /// 词典条目 → 搜索结果项
    ///
    /// `nonisolated static`：纯拼装，不碰实例状态。把这一步单独拿出来，
    /// 「条目长什么样」才能在没有系统词典的测试里被固定住。
    nonisolated static func dictionaryItem(
        for entry: DictionaryEntry, word: String
    ) -> [SearchableItem] {
        let brief = entry.briefMeaning ?? entry.word
        let subtitle = [entry.word, entry.phonetic].filter { !$0.isEmpty }.joined(separator: " · ")
        return [
            SearchableItem(
                id: "translator.dict",
                pluginID: Self.id,
                title: brief,
                subtitle: subtitle.isEmpty ? "词典" : subtitle,
                icon: "text.book.closed",
                relevance: 0.9,
                shortcutHint: "⏎ 打开",
                action: {
                    EventBus.shared.post(
                        NavigateEvent(pluginID: Self.id, context: ["query": word]))
                }
            )
        ]
    }

    /// 文本：一条译文
    private func translationItems(for text: String) async -> [SearchableItem] {
        do {
            let outcome = try await service.translateOnce(
                text, source: TranslationLanguages.autoCode, target: PluginDefaults.targetLanguage())
            guard !outcome.result.isEmpty else { return [] }
            let from = TranslationLanguages.label(for: outcome.effective.source)
            let to = TranslationLanguages.label(for: outcome.effective.target)
            return [
                SearchableItem(
                    id: "translator.result",
                    pluginID: Self.id,
                    title: outcome.result,
                    subtitle: "\(from) → \(to)",
                    icon: "character.book.closed",
                    relevance: 0.85,
                    shortcutHint: "⏎ 复制",
                    action: { [weak self] in
                        self?.history.record(
                            source: text, result: outcome.result,
                            from: outcome.effective.source, to: outcome.effective.target)
                        EventBus.shared.post(CopyToClipboardEvent(text: outcome.result))
                    }
                )
            ]
        } catch {
            log.warning("内联翻译失败：\(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func makeView() -> AnyView {
        AnyView(TranslatorView(plugin: self, buffer: buffer).prefillFromPluginContext(buffer))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
