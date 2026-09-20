// TranslatorModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 翻译模块
///
/// 使用系统 NLLanguageRecognizer 自动检测语言，
/// 调用 Translation 框架进行多语言翻译。
@MainActor
public final class TranslatorModule: QuickModule {

    public static let id = "translator"
    public static let name = "翻译"
    public static let icon = "character.book.closed"

    public var isEnabled = true

    private let log = QuickLog.module(TranslatorModule.id)

    /// 翻译服务
    private let service = TranslationService()

    public init() {}

    // MARK: - QuickModule 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        // "翻译 ..." 或 "tr ..." 或 "translate ..."
        let triggers: [(String, String)] = [
            ("翻译 ", "翻译"),
            ("tr ", "tr"),
            ("translate ", "translate"),
            ("fy ", "fy")
        ]

        guard let match = triggers.first(where: { query.lowercased().hasPrefix($0.0) }) else {
            return []
        }

        let text = String(query.dropFirst(match.0.count))
        guard !text.isEmpty else { return [] }

        let result = await service.translate(text)
        guard let result, !result.isEmpty else { return [] }

        return [
            SearchableItem(
                id: "translator.result",
                moduleID: Self.id,
                title: result,
                subtitle: "翻译结果",
                icon: "character.book.closed",
                relevance: 0.85,
                shortcutHint: "⏎ 复制",
                action: {
                    EventBus.shared.post(CopyToClipboardEvent(text: result))
                }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(TranslatorView(service: service))
    }

    public func activate() {
        log.notice("模块已激活")
    }

    public func deactivate() {
        log.notice("模块已停用")
    }
}
