// TranslatorView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 翻译插件视图
///
/// 三块：输入卡、译文卡、词典卡（输入是单词时）。输入防抖后自动翻译，切换语言立即重译。
struct TranslatorView: View {

    let plugin: TranslatorPlugin
    @Bindable var buffer: TextBuffer

    @State private var sourceLang = TranslationLanguages.autoCode
    @State private var targetLang = PluginDefaults.defaultTargetLanguage
    @State private var dictionaryEntry: DictionaryEntry?
    @State private var showHistory = false

    private var service: TranslationService { plugin.service }
    private var sourceText: String { buffer.text }

    /// 触发翻译的防抖间隔
    ///
    /// 每敲一个字都翻译一次会既费算力又闪烁：`NLLanguageRecognizer` 会跟着短词反复改判，
    /// 端上翻译也要起一次会话。停手 400ms 才译，输入过程中只更新词典（离线、即时）。
    private static let debounceDelay = Duration.milliseconds(400)

    /// 一次翻译请求的全部输入。作为 `.task(id:)` 的 id，任一变化都重新防抖 ——
    /// SwiftUI 会在 id 变化时自动取消上一个 task，不需要自己管取消。
    private struct TranslationRequest: Equatable {
        let text: String
        let source: String
        let target: String
    }

    var body: some View {
        VStack(spacing: 0) {
            languageBar
            Divider().opacity(0.4)
            content
        }
        .task { bootstrap() }
        .task(id: request) { await runDebouncedTranslation() }
        .onChange(of: service.isTranslating) { _, translating in recordWhenDone(translating) }
        .sheet(isPresented: $showHistory) {
            TranslationHistorySheet(store: plugin.history) { item in
                buffer.text = item.sourceText
                sourceLang = item.from
                targetLang = item.to
                showHistory = false
            }
        }
    }

    private var request: TranslationRequest {
        TranslationRequest(text: buffer.text, source: sourceLang, target: targetLang)
    }

    // MARK: - 语言栏

    private var languageBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Picker("", selection: $sourceLang) {
                ForEach(TranslationLanguages.sourceOptions) { option in
                    Text(option.label).tag(option.code)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 140)

            Button {
                swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(DesignTokens.Typography.inlineIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .help("交换源语言与目标语言")

            Picker("", selection: $targetLang) {
                ForEach(TranslationLanguages.all) { option in
                    Text(option.label).tag(option.code)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 140)

            Spacer(minLength: DesignTokens.Spacing.sm)

            if let detected = service.detectedLanguage, sourceLang == TranslationLanguages.autoCode {
                Text("识别：\(TranslationLanguages.label(for: detected))")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(DesignTokens.Typography.inlineIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .help("翻译历史")
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    // MARK: - 主体

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                inputCard
                resultCard
                if let entry = dictionaryEntry, !entry.isEmpty {
                    dictionaryCard(entry)
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            TextEditor(text: $buffer.text)
                .font(DesignTokens.Typography.rowTitle)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 88, maxHeight: 160)
                .padding(DesignTokens.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .fill(DesignTokens.Colors.cardFill)
                )
                .overlay(alignment: .topLeading) {
                    if sourceText.isEmpty {
                        Text("输入要翻译的文本，或直接输入一个单词查词典…")
                            .font(DesignTokens.Typography.rowTitle)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.md)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: DesignTokens.Spacing.sm) {
                Text("\(sourceText.count) 字")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

                Spacer(minLength: DesignTokens.Spacing.sm)

                if !sourceText.isEmpty {
                    iconButton("speaker.wave.2", help: "朗读原文") {
                        plugin.speech.speak(sourceText, language: spokenSource)
                    }
                    iconButton("xmark", help: "清空") {
                        buffer.text = ""
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        if service.isTranslating {
            card {
                HStack(spacing: DesignTokens.Spacing.md) {
                    ProgressView().controlSize(.small)
                    Text("翻译中…")
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
        } else if let error = service.errorMessage {
            card {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(DesignTokens.Typography.inlineIcon)
                        .foregroundStyle(DesignTokens.Colors.warning)
                    Text(error)
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if !service.result.isEmpty {
            card {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    HStack {
                        Text("译文")
                            .font(DesignTokens.Typography.sectionHeader)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Spacer()
                        iconButton("speaker.wave.2", help: "朗读译文") {
                            plugin.speech.speak(service.result, language: service.effective.target)
                        }
                        iconButton("doc.on.doc", help: "复制译文") {
                            EventBus.shared.post(CopyToClipboardEvent(text: service.result))
                        }
                    }
                    Text(service.result)
                        .font(DesignTokens.Typography.rowTitle)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func dictionaryCard(_ entry: DictionaryEntry) -> some View {
        card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(entry.word)
                        .font(DesignTokens.Typography.panelTitle)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    iconButton("speaker.wave.2", help: "朗读单词") {
                        plugin.speech.speak(entry.word, language: "en")
                    }
                    Spacer()
                    iconButton("doc.on.doc", help: "复制词条") {
                        EventBus.shared.post(CopyToClipboardEvent(text: entry.displayText))
                    }
                }

                if !entry.phonetic.isEmpty {
                    Text(entry.phonetic)
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.progress)
                }

                ForEach(Array(entry.senses.enumerated()), id: \.offset) { _, sense in
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                        if !sense.pos.isEmpty {
                            Text(sense.pos)
                                .font(DesignTokens.Typography.keyCap)
                                .foregroundStyle(DesignTokens.Colors.progress)
                                .frame(width: 34, alignment: .leading)
                        }
                        Text(sense.meaning)
                            .font(DesignTokens.Typography.rowTrailing)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !entry.examples.isEmpty {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        ForEach(Array(entry.examples.prefix(4).enumerated()), id: \.offset) { _, example in
                            Text("▸ \(example)")
                                .font(DesignTokens.Typography.keyCap)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, DesignTokens.Spacing.xs)
                }
            }
        }
    }

    // MARK: - 复用

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignTokens.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(DesignTokens.Colors.cardFill)
            )
    }

    private func iconButton(
        _ symbol: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(DesignTokens.Typography.inlineIcon)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(
                    width: DesignTokens.Size.windowControlButton,
                    height: DesignTokens.Size.windowControlButton
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - 行为

    private var spokenSource: String {
        if sourceLang != TranslationLanguages.autoCode { return sourceLang }
        return service.detectedLanguage ?? LanguageDetector.detect(sourceText)
    }

    private func bootstrap() {
        targetLang = PluginDefaults.targetLanguage()
    }

    /// 防抖翻译：词典立即查（离线、快），翻译停手 400ms 才发
    ///
    /// 由 `.task(id: request)` 驱动：输入、源语言、目标语言任一变化都会取消上一个 task
    /// 并重跑这里，所以「快速连打」只会译最后一次。
    @MainActor
    private func runDebouncedTranslation() async {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            service.cancel()
            dictionaryEntry = nil
            return
        }
        dictionaryEntry = isLookupCandidate(trimmed) ? plugin.dictionary.lookup(trimmed) : nil
        do {
            try await Task.sleep(for: Self.debounceDelay)
        } catch {
            // 被新的输入取消：直接退出，不要发翻译
            return
        }
        guard !Task.isCancelled else { return }
        service.requestTranslation(text: trimmed, source: sourceLang, target: targetLang)
    }

    /// 是否值得查词典：单个词（无空白、不太长）
    private func isLookupCandidate(_ text: String) -> Bool {
        guard text.count <= 30 else { return false }
        return !text.contains(where: { $0.isWhitespace })
    }

    private func swapLanguages() {
        let swapped = LanguageResolution.swapped(
            source: sourceLang, target: targetLang, effective: service.effective)
        sourceLang = swapped.source
        targetLang = swapped.target
    }

    private func recordWhenDone(_ translating: Bool) {
        guard !translating, !service.result.isEmpty else { return }
        plugin.history.record(
            source: sourceText, result: service.result,
            from: service.effective.source, to: service.effective.target)
    }
}

// MARK: - 历史

private struct TranslationHistorySheet: View {

    let store: TranslationHistoryStore
    let onSelect: (TranslationHistoryItem) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("翻译历史")
                    .font(DesignTokens.Typography.panelTitle)
                Spacer()
                if !store.items.isEmpty {
                    Button("清空") { store.clear() }
                        .buttonStyle(.borderless)
                }
                Button("完成") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding(DesignTokens.Spacing.lg)

            Divider().opacity(0.4)

            if store.items.isEmpty {
                Text("还没有翻译记录")
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.items) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                                    Text(item.sourceText)
                                        .font(DesignTokens.Typography.rowTitle)
                                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                                        .lineLimit(1)
                                    Text(item.resultText)
                                        .font(DesignTokens.Typography.rowTrailing)
                                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                                        .lineLimit(1)
                                    Text(
                                        "\(TranslationLanguages.label(for: item.from)) → \(TranslationLanguages.label(for: item.to))"
                                    )
                                    .font(DesignTokens.Typography.keyCap)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DesignTokens.Spacing.lg)
                                .padding(.vertical, DesignTokens.Spacing.md)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(width: 420, height: 480)
    }
}
