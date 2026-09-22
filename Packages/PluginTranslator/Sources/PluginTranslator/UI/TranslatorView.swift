// TranslatorView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 翻译插件视图
struct TranslatorView: View {

    let service: TranslationService

    /// 输入文本归插件所有：主面板与分离窗口共享同一份，分离时内容自然带过去
    @Bindable var buffer: TextBuffer

    private var sourceText: String {
        get { buffer.text }
        nonmutating set { buffer.text = newValue }
    }
    @State private var resultText = ""

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            // 标题
            HStack {
                Image(systemName: "character.book.closed")
                    .font(DesignTokens.Typography.headerIcon)
                Text("翻译")
                    .font(DesignTokens.Typography.panelTitle)
                Spacer()
                if let lang = service.detectedLanguage {
                    Text("检测: \(lang)")
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            .foregroundStyle(DesignTokens.Colors.textPrimary)

            // 源文本
            TextEditor(text: $buffer.text)
                .font(DesignTokens.Typography.rowTitle)
                .scrollContentBackground(.hidden)
                .padding(DesignTokens.Spacing.md)
                .background(DesignTokens.Colors.cardFill)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                .frame(minHeight: 80)
                .overlay(alignment: .topLeading) {
                    if sourceText.isEmpty {
                        Text("输入要翻译的文本…")
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(DesignTokens.Spacing.md)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                }

            // 翻译按钮
            Button {
                Task {
                    resultText = await service.translate(sourceText) ?? ""
                }
            } label: {
                Label("翻译", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(sourceText.isEmpty || service.isTranslating)

            // 结果
            if !resultText.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    HStack {
                        Text("翻译结果")
                            .font(DesignTokens.Typography.sectionHeader)
                        Spacer()
                        Button {
                            EventBus.shared.post(CopyToClipboardEvent(text: resultText))
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                    }

                    Text(resultText)
                        .font(DesignTokens.Typography.rowTitle)
                        .textSelection(.enabled)
                        .padding(DesignTokens.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.Colors.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                }
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.xxl)
    }
}
