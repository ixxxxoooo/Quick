// ChatSession.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// AI 对话会话
///
/// 管理对话历史和 AI 请求。
/// 预留多模型 Provider 接口，可扩展 OpenAI / Claude 等。
@MainActor
@Observable
final class ChatSession {

    private(set) var messages: [ChatMessage] = []
    private(set) var isStreaming = false

    /// 发送消息
    func send(_ text: String) async {
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        isStreaming = true
        defer { isStreaming = false }

        // 预留 AI Provider 接口
        // 默认回复（开发占位）
        let response = ChatMessage(
            role: .assistant,
            content: "AI 对话功能需要配置 API Key。请在设置中配置 OpenAI 或 Claude API。\n\n你发送了：\(text)"
        )
        messages.append(response)
    }

    /// 清空对话
    func clear() {
        messages.removeAll()
    }
}
