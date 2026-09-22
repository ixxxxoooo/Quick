// TranslatorPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 翻译插件
///
/// 使用系统 NLLanguageRecognizer 自动检测语言，
/// 调用 Translation 框架进行多语言翻译。
@MainActor
public final class TranslatorPlugin: QuickPlugin {

    public static let id = "translator"
    public static let name = "翻译"
    public static let icon = "character.book.closed"
    public static let description = "多语言文本实时互译，支持自动识别源语言、词典释义查询与一键复制译文。"
    public static let triggerWords = ["翻译", "tr", "translate", "translation"]

    public var isEnabled = true

    private let log = QuickLog.plugin(TranslatorPlugin.id)

    /// 翻译服务
    private let service = TranslationService()

    public init() {}

    // MARK: - QuickPlugin 协议

    public func accepts(query: String) -> Bool {
        TranslatorQuery.text(in: query) != nil
    }

    public func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }
        return await searchItems(query: query)
    }

    public func searchItems(query: String) async -> [SearchableItem] {
        // 触发词解析是纯逻辑，见 TranslatorQuery（"翻译 ..." / "tr ..." / "translate ..." / "fy ..."）
        guard let text = TranslatorQuery.text(in: query) else { return [] }

        let result = await service.translate(text)
        guard let result, !result.isEmpty else { return [] }

        return [
            SearchableItem(
                id: "translator.result",
                pluginID: Self.id,
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

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(TranslatorView(service: service, buffer: buffer))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
