// ChatView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// AI 对话视图
struct ChatView: View {

    let session: ChatSession
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            // 对话历史
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.md) {
                    ForEach(session.messages) { msg in
                        HStack {
                            if msg.role == .user { Spacer() }
                            VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 4) {
                                Text(msg.role == .user ? "你" : "AI")
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                                Text(msg.content)
                                    .font(DesignTokens.Typography.rowTitle)
                                    .padding(DesignTokens.Spacing.lg)
                                    .background {
                                        RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                                            .fill(
                                                msg.role == .user
                                                    ? Color.blue.opacity(0.15) : DesignTokens.Colors.cardFill)
                                    }
                                    .textSelection(.enabled)
                            }
                            if msg.role == .assistant { Spacer() }
                        }
                    }
                }
                .padding(DesignTokens.Spacing.xl)
            }

            Divider().opacity(0.3)

            // 输入区域
            HStack(spacing: DesignTokens.Spacing.md) {
                TextField("输入消息…", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.rowTitle)
                    .onSubmit { sendMessage() }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || session.isStreaming)
            }
            .padding(DesignTokens.Spacing.xl)
        }
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""
        Task { await session.send(text) }
    }
}

/// AI 设置视图
struct AISettingsView: View {
    @AppStorage("ai.apiKey") private var apiKey = ""
    @AppStorage("ai.provider") private var provider = "openai"

    var body: some View {
        Form {
            Picker("AI 服务", selection: $provider) {
                Text("OpenAI").tag("openai")
                Text("Claude").tag("claude")
            }
            SecureField("API Key", text: $apiKey)
        }
        .formStyle(.grouped)
        .padding()
    }
}
