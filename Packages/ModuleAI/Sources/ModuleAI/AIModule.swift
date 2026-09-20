// AIModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// AI 对话模块
///
/// 多模型流式对话。支持 OpenAI / Claude 等多种 AI 服务。
@MainActor
public final class AIModule: QuickModule {

    public static let id = "ai"
    public static let name = "AI 对话"
    public static let icon = "sparkles"
    public static let triggerWords = ["ai", "聊天", "chat", "问", "ask", "gpt", "claude"]

    public var isEnabled = true

    private let log = QuickLog.module(AIModule.id)

    private let chatSession = ChatSession()

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        // 用整词匹配而不是 contains：否则 email / wait / task 都会误触发本模块
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }

        return [
            SearchableItem(
                id: "ai.chat",
                moduleID: Self.id,
                title: "AI 对话",
                subtitle: "与 AI 助手对话",
                icon: "sparkles",
                relevance: 0.7,
                action: {
                    EventBus.shared.post(NavigateEvent(moduleID: "ai"))
                }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(ChatView(session: chatSession))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(AISettingsView())
    }

    public func activate() {
        log.notice("模块已激活，当前会话 \(self.chatSession.messages.count, privacy: .public) 条消息")
    }

    public func deactivate() {
        log.notice("模块已停用")
    }
}
